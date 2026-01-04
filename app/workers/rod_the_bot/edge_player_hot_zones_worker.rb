module RodTheBot
  class EdgePlayerHotZonesWorker
    include Sidekiq::Worker
    include EdgePlayerSelector
    include PlayerImageHelper

    def perform(_game_id = nil)
      return if NhlApi.preseason?

      # Get eligible players (hot scorers with elite shot zones)
      eligible_players = select_eligible_players(
        last_n_games: 5,
        min_games_played: 4,
        criteria: :hot_zones
      )

      return if eligible_players.empty?

      # Randomly select one
      selected_player = eligible_players.sample

      # Fetch shot location data
      shot_data = NhlApi.fetch_skater_shot_location_detail(selected_player[:id])
      return unless shot_data && shot_data["shotLocationDetails"]

      # Get player headshot
      player_headshot = fetch_player_headshot(selected_player[:id])

      # Format and post
      post_text = format_hot_zones_spotlight(selected_player, shot_data)
      RodTheBot::Post.perform_async(post_text, nil, nil, nil, [player_headshot]) if post_text
    rescue => e
      Rails.logger.error("EdgePlayerHotZonesWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_hot_zones_spotlight(player, shot_data)
      # Find zones where player is elite (80th+ percentile in goals)
      elite_zones = shot_data["shotLocationDetails"].select do |zone|
        (zone["goalsPercentile"] || 0) >= 0.80
      end.sort_by { |z| -(z["goalsPercentile"] || 0) }

      return nil if elite_zones.length < 2

      # Get top 3 zones
      top_zones = elite_zones.first(3)

      # Get player info
      player_landing = NhlApi.fetch_player_landing_feed(player[:id])
      sweater_number = player_landing.dig("sweaterNumber")

      post = <<~POST
        🎯 WHERE #{player[:name].upcase} SCORES

        #{player[:name]}'s danger zones:
      POST

      top_zones.each do |zone|
        goals = zone["goals"]
        percentile = (zone["goalsPercentile"] * 100).round(0)
        area = zone["area"]
        post += "• #{area}: #{goals}G (#{percentile}th percentile)\n"
      end

      if sweater_number
        post += "\nWatch for ##{sweater_number} in these areas tonight."
      end

      post
    end
  end
end
