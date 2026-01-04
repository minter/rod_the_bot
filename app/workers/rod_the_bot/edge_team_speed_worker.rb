module RodTheBot
  class EdgeTeamSpeedWorker
    include Sidekiq::Worker
    include PlayerImageHelper

    def perform(_game_id = nil)
      return if NhlApi.preseason?

      team_id = ENV["NHL_TEAM_ID"].to_i
      speed_data = NhlApi.fetch_team_skating_speed_detail(team_id)
      return unless speed_data && speed_data["skatingSpeedDetails"]&.any?

      our_team_abbrev, opponent_team_abbrev, opponent_speed_data = fetch_opponent_data(team_id)

      # Get player IDs for headshots
      player_ids = []
      player_ids << speed_data.dig("topSkatingSpeeds", 0, "player", "id") if speed_data.dig("topSkatingSpeeds", 0, "player")
      player_ids << opponent_speed_data.dig("topSkatingSpeeds", 0, "player", "id") if opponent_speed_data&.dig("topSkatingSpeeds", 0, "player")

      headshots = fetch_player_headshots(player_ids)

      post_text = format_team_speed_post(speed_data, opponent_speed_data, our_team_abbrev, opponent_team_abbrev)
      RodTheBot::Post.perform_async(post_text, nil, nil, nil, headshots) if post_text
    rescue => e
      Rails.logger.error("EdgeTeamSpeedWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def fetch_opponent_data(team_id)
      today_game = NhlApi.todays_game
      return [nil, nil, nil] unless today_game

      game_feed = NhlApi.fetch_landing_feed(today_game["id"])
      return [nil, nil, nil] unless game_feed

      home_id = game_feed.dig("homeTeam", "id")
      away_id = game_feed.dig("awayTeam", "id")

      if home_id == team_id
        our_abbrev = game_feed.dig("homeTeam", "abbrev")
        opp_abbrev = game_feed.dig("awayTeam", "abbrev")
        opponent_id = away_id
      else
        our_abbrev = game_feed.dig("awayTeam", "abbrev")
        opp_abbrev = game_feed.dig("homeTeam", "abbrev")
        opponent_id = home_id
      end

      opp_speed_data = opponent_id ? NhlApi.fetch_team_skating_speed_detail(opponent_id) : nil

      [our_abbrev, opp_abbrev, opp_speed_data]
    end

    def format_team_speed_post(data, opponent_data, our_team_abbrev, opponent_team_abbrev)
      all_positions = data["skatingSpeedDetails"]&.find { |d| d["positionCode"] == "all" }
      return nil unless all_positions

      our_team_abbrev ||= ENV["NHL_TEAM_ABBREVIATION"]

      post = "💨 SPEED MATCHUP\n\n"
      post += format_team_speed_stats(data, all_positions, our_team_abbrev)

      if opponent_data && opponent_team_abbrev
        opponent_positions = opponent_data["skatingSpeedDetails"]&.find { |d| d["positionCode"] == "all" }
        post += "\n#{format_team_speed_stats(opponent_data, opponent_positions, opponent_team_abbrev)}" if opponent_positions
      end

      post
    end

    def format_team_speed_stats(data, all_positions, team_abbrev)
      max_speed = all_positions["maxSkatingSpeed"]
      bursts_over_22 = all_positions["burstsOver22"]
      bursts_20_to_22 = all_positions["bursts20To22"]

      return "" unless max_speed && bursts_over_22 && bursts_20_to_22

      max_speed_val = max_speed["imperial"]&.round(2)
      max_speed_rank = max_speed["rank"]
      bursts_over_22_val = bursts_over_22["value"]
      bursts_over_22_rank = bursts_over_22["rank"]
      bursts_20_to_22_val = bursts_20_to_22["value"]
      bursts_20_to_22_rank = bursts_20_to_22["rank"]

      # Get top speed player name if available
      top_speed_player = data["topSkatingSpeeds"]&.first
      player_name = if top_speed_player && top_speed_player["player"]
        "#{top_speed_player["player"]["firstName"]["default"]} #{top_speed_player["player"]["lastName"]["default"]}"
      else
        nil
      end

      stats = <<~STATS
        #{team_abbrev} speed:
        • Top speed: #{max_speed_val} mph (##{max_speed_rank} in NHL)
      STATS

      if player_name
        stats += "• Fastest: #{player_name}\n"
      end

      stats += "• #{bursts_over_22_val} bursts over 22 mph (##{bursts_over_22_rank})\n"
      stats += "• #{bursts_20_to_22_val} bursts 20-22 mph (##{bursts_20_to_22_rank})\n"

      stats
    end
  end
end
