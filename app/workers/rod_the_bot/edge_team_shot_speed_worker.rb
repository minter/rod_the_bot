module RodTheBot
  class EdgeTeamShotSpeedWorker
    include Sidekiq::Worker
    include PlayerImageHelper

    def perform(game_id = nil)
      return if NhlApi.preseason?

      team_id = ENV["NHL_TEAM_ID"].to_i
      shot_data = NhlApi.fetch_team_shot_speed_detail(team_id)
      return unless shot_data && shot_data["shotSpeedDetails"]&.any?

      our_team_abbrev, opponent_team_abbrev, opponent_shot_data = fetch_opponent_data(game_id, team_id)

      # Get player IDs for headshots
      player_ids = []
      player_ids << shot_data.dig("hardestShots", 0, "player", "id") if shot_data.dig("hardestShots", 0, "player")
      player_ids << opponent_shot_data.dig("hardestShots", 0, "player", "id") if opponent_shot_data&.dig("hardestShots", 0, "player")

      headshots = fetch_player_headshots(player_ids)

      post_text = format_team_shot_speed_post(shot_data, opponent_shot_data, our_team_abbrev, opponent_team_abbrev)
      RodTheBot::Post.perform_async(post_text, nil, nil, nil, headshots) if post_text
    rescue => e
      Rails.logger.error("EdgeTeamShotSpeedWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def fetch_opponent_data(game_id, team_id)
      return [nil, nil, nil] unless game_id

      game_feed = NhlApi.fetch_landing_feed(game_id)
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

      opp_shot_data = opponent_id ? NhlApi.fetch_team_shot_speed_detail(opponent_id) : nil

      [our_abbrev, opp_abbrev, opp_shot_data]
    end

    def format_team_shot_speed_post(data, opponent_data, our_team_abbrev, opponent_team_abbrev)
      all_positions = data["shotSpeedDetails"]&.find { |d| d["position"] == "all" }
      return nil unless all_positions

      our_team_abbrev ||= ENV["NHL_TEAM_ABBREVIATION"]

      post = "🎯 SHOT SPEED PREVIEW\n\n"
      post += format_team_shot_stats(data, all_positions, our_team_abbrev)

      if opponent_data && opponent_team_abbrev
        opponent_positions = opponent_data["shotSpeedDetails"]&.find { |d| d["position"] == "all" }
        post += "\n#{format_team_shot_stats(opponent_data, opponent_positions, opponent_team_abbrev)}" if opponent_positions
      end

      post
    end

    def format_team_shot_stats(data, all_positions, team_abbrev)
      top_shot_speed = all_positions["topShotSpeed"]
      avg_shot_speed = all_positions["avgShotSpeed"]

      return "" unless top_shot_speed && avg_shot_speed

      top_speed_val = top_shot_speed["imperial"]&.round(2)
      top_speed_rank = top_shot_speed["rank"]
      avg_speed_val = avg_shot_speed["imperial"]&.round(2)
      avg_speed_rank = avg_shot_speed["rank"]

      # Get hardest shot player name if available
      hardest_shot_player = data["hardestShots"]&.first
      player_name = if hardest_shot_player && hardest_shot_player["player"]
        "#{hardest_shot_player["player"]["firstName"]["default"]} #{hardest_shot_player["player"]["lastName"]["default"]}"
      end

      stats = <<~STATS
        #{team_abbrev} shot speed:
        • Average: #{avg_speed_val} mph (##{avg_speed_rank} in NHL)
        • Hardest: #{top_speed_val} mph (##{top_speed_rank})
      STATS

      if player_name
        stats += "• Hardest shot: #{player_name}\n"
      end

      stats
    end
  end
end
