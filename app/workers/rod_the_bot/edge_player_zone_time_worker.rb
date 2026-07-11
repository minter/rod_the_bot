module RodTheBot
  class EdgePlayerZoneTimeWorker
    include Sidekiq::Worker
    include WorkerErrorHandling
    include EdgePlayerSelector
    include PlayerImageHelper

    def perform(game_id = nil)
      return if Nhl::SeasonCalendar.preseason?

      # Get eligible players (hot + elite zone control)
      eligible_players = select_eligible_players(
        last_n_games: 5,
        min_games_played: 4,
        criteria: :zone_control_elite
      )

      return if eligible_players.empty?

      # Randomly select one
      selected_player = eligible_players.sample

      # Fetch EDGE data
      edge_data = Nhl::EdgeClient.fetch_skater_zone_time(selected_player[:id])
      return unless edge_data && edge_data["zoneTimeDetails"]

      # Get player headshot
      player_headshot = fetch_player_headshot(selected_player[:id])

      # Format and post
      post_text = format_zone_time_spotlight(selected_player, edge_data)
      RodTheBot::Post.perform_async(post_text, nil, nil, nil, [player_headshot]) if post_text
    rescue => e
      retry_job(e, game_id: game_id, operation: "edge_player_zone_time")
    end

    private

    def format_zone_time_spotlight(player, edge_data)
      all_situations = edge_data["zoneTimeDetails"].find { |d| d["strengthCode"] == "all" }
      return nil unless all_situations

      oz_pct = (all_situations["offensiveZonePctg"] * 100).round(1)
      oz_percentile = (all_situations["offensiveZonePercentile"] * 100).round(0)
      dz_pct = (all_situations["defensiveZonePctg"] * 100).round(1)
      dz_percentile = (all_situations["defensiveZonePercentile"] * 100).round(0)

      oz_starts_pct = (edge_data.dig("zoneStarts", "offensiveZoneStartsPctg") * 100).round(1)
      oz_starts_percentile = (edge_data.dig("zoneStarts", "offensiveZoneStartsPctgPercentile") * 100).round(0)

      # Get season totals
      player_landing = Nhl::PlayerClient.landing(player[:id])
      season_stats = player_landing.dig("featuredStats", "regularSeason", "subSeason")
      goals = season_stats["goals"]
      assists = season_stats["assists"]
      points = season_stats["points"]

      <<~POST
        🔍 EDGE SPOTLIGHT: #{player[:name]}

        Zone control this season:
        • #{oz_pct}% off. zone time (#{oz_percentile}th percentile)
        • #{dz_pct}% def. zone time (#{dz_percentile}th percentile)
        • #{oz_starts_pct}% off. zone starts (#{oz_starts_percentile}th percentile)

        Season totals: #{goals}G-#{assists}A = #{points} points
      POST
    end
  end
end
