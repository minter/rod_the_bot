module RodTheBot
  class EdgePlayerWorkloadWorker
    include Sidekiq::Worker
    include EdgePlayerSelector
    include PlayerImageHelper

    def perform(_game_id = nil)
      return if NhlApi.preseason?

      # Get eligible players (hot streak + high workload)
      # Note: criteria changed to check last 3 games for "truly hot"
      eligible_players = select_eligible_players(
        last_n_games: 3,
        min_games_played: 3,
        criteria: :high_workload
      )

      return if eligible_players.empty?

      # Randomly select one
      selected_player = eligible_players.sample

      # Fetch skating distance data
      distance_data = NhlApi.fetch_skater_skating_distance_detail(selected_player[:id])
      return unless distance_data && distance_data["skatingDistanceLast10"]

      # Get player headshot
      player_headshot = fetch_player_headshot(selected_player[:id])

      # Format and post
      post_text = format_workload_spotlight(selected_player, distance_data)
      RodTheBot::Post.perform_async(post_text, nil, nil, nil, [player_headshot]) if post_text
    rescue => e
      Rails.logger.error("EdgePlayerWorkloadWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_workload_spotlight(player, distance_data)
      recent_games = distance_data["skatingDistanceLast10"].first(3)
      return nil if recent_games.length < 3

      # Calculate averages
      avg_distance = (recent_games.sum { |g| g.dig("distanceSkatedAll", "imperial") || 0 } / recent_games.length.to_f).round(1)
      avg_toi_seconds = recent_games.sum { |g| g["toiAll"] || 0 } / recent_games.length.to_f
      avg_toi_minutes = (avg_toi_seconds / 60.0).round(0)

      # Get PP usage
      avg_pp_toi_seconds = recent_games.sum { |g| g["toiPP"] || 0 } / recent_games.length.to_f
      avg_pp_toi_minutes = (avg_pp_toi_seconds / 60.0).round(1)

      # Get season totals
      player_landing = NhlApi.fetch_player_landing_feed(player[:id])
      season_stats = player_landing.dig("featuredStats", "regularSeason", "subSeason")
      goals = season_stats["goals"]
      assists = season_stats["assists"]
      points = season_stats["points"]

      <<~POST
        🔥 #{player[:name].upcase} WORKLOAD

        #{player[:name]}'s last #{recent_games.length} games:
        • #{player[:goals]}G-#{player[:points] - player[:goals]}A = #{player[:points]} points
        • Averaging #{avg_distance} miles skated/game
        • #{avg_toi_minutes}+ minutes TOI per game
        • #{avg_pp_toi_minutes} min/game on PP

        Season totals: #{goals}G-#{assists}A = #{points} points
      POST
    end
  end
end
