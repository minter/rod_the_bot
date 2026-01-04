module RodTheBot
  class EdgeSpeedDemonLeaderboardWorker
    include Sidekiq::Worker
    include PlayerImageHelper

    def perform(_game_id = nil)
      return if NhlApi.preseason?

      # Get team ID from environment
      team_id = ENV["NHL_TEAM_ID"].to_i

      # Fetch team speed data
      speed_data = NhlApi.fetch_team_skating_speed_detail(team_id)
      return unless speed_data && speed_data["topSkatingSpeeds"]&.any?

      # Get current roster to verify players are active
      roster = NhlApi.roster(ENV["NHL_TEAM_ABBREVIATION"])
      roster_ids = roster.keys.map(&:to_i)

      # Format and post
      post_text, player_ids = format_speed_leaderboard_post(speed_data, roster_ids)

      if post_text
        headshots = fetch_player_headshots(player_ids)
        RodTheBot::Post.perform_async(post_text, nil, nil, nil, headshots)
      end
    rescue => e
      Rails.logger.error("EdgeSpeedDemonLeaderboardWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_speed_leaderboard_post(data, roster_ids)
      top_speeds = data["topSkatingSpeeds"] || []
      return [nil, []] if top_speeds.empty?

      # Filter to only players on active roster and get unique players (top 3)
      unique_players = []
      player_ids = []
      seen_player_ids = Set.new

      top_speeds.each do |speed_entry|
        player = speed_entry["player"]
        next unless player

        player_id = player["id"]&.to_i
        next unless player_id && roster_ids.include?(player_id)
        next if seen_player_ids.include?(player_id)

        seen_player_ids.add(player_id)
        player_ids << player_id
        unique_players << {
          name: "#{player["firstName"]["default"]} #{player["lastName"]["default"]}",
          speed: speed_entry["skatingSpeed"]["imperial"]&.round(2)
        }

        break if unique_players.length >= 3
      end

      return [nil, []] if unique_players.empty?

      team_abbrev = ENV["NHL_TEAM_ABBREVIATION"]
      post = <<~POST
        💨 SPEED DEMONS

        Top 3 fastest #{team_abbrev} players:
      POST

      unique_players.each_with_index do |player, index|
        post += "#{index + 1}. #{player[:name]}: #{player[:speed]} mph\n"
      end

      [post, player_ids]
    end
  end
end
