module RodTheBot
  class EdgeTeamPreviewWorker
    include Sidekiq::Worker

    def perform(_game_id = nil)
      return if NhlApi.preseason?

      team_id = ENV["NHL_TEAM_ID"].to_i
      zone_data = NhlApi.fetch_team_zone_time_details(team_id)
      return unless zone_data && zone_data["zoneTimeDetails"]&.any?

      our_team_abbrev, opponent_team_abbrev, opponent_zone_data = fetch_opponent_data(team_id)

      post_text = format_team_zone_time_post(zone_data, opponent_zone_data, our_team_abbrev, opponent_team_abbrev)
      RodTheBot::Post.perform_async(post_text) if post_text
    rescue => e
      Rails.logger.error("EdgeTeamPreviewWorker error: #{e.message}")
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

      opp_zone_data = opponent_id ? NhlApi.fetch_team_zone_time_details(opponent_id) : nil

      [our_abbrev, opp_abbrev, opp_zone_data]
    end

    def format_team_zone_time_post(data, opponent_data, our_team_abbrev, opponent_team_abbrev)
      all_situations = data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "all" }
      return nil unless all_situations

      our_team_abbrev ||= ENV["NHL_TEAM_ABBREVIATION"]

      post = "⚡ BY THE NUMBERS ⚡\n\n"
      post += format_team_stats(data, all_situations, our_team_abbrev)

      if opponent_data && opponent_team_abbrev
        opponent_situations = opponent_data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "all" }
        post += "\n#{format_team_stats(opponent_data, opponent_situations, opponent_team_abbrev)}" if opponent_situations
      end

      post
    end

    def format_team_stats(data, all_situations, team_abbrev)
      oz_pct = (all_situations["offensiveZonePctg"] * 100).round(1)
      oz_rank = all_situations["offensiveZoneRank"]
      dz_pct = (all_situations["defensiveZonePctg"] * 100).round(1)
      dz_rank = all_situations["defensiveZoneRank"]

      shot_diff = data["shotDifferential"] || {}
      shot_diff_val = shot_diff["shotAttemptDifferential"]&.round(1)
      shot_diff_rank = shot_diff["shotAttemptDifferentialRank"]

      stats = <<~STATS
        #{team_abbrev} zone control:
        • #{oz_pct}% off. zone time (##{oz_rank} in NHL)
        • #{dz_pct}% def. zone time (##{dz_rank} least)
      STATS

      if shot_diff_val && shot_diff_rank
        sign = (shot_diff_val >= 0) ? "+" : ""
        stats += "• #{sign}#{shot_diff_val} shot diff. per game (##{shot_diff_rank})\n"
      end

      stats
    end
  end
end
