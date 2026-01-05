module RodTheBot
  class EdgeSpecialTeamsWorker
    include Sidekiq::Worker

    def perform(game_id = nil)
      return if NhlApi.preseason?

      team_id = ENV["NHL_TEAM_ID"].to_i
      zone_data = NhlApi.fetch_team_zone_time_details(team_id)
      return unless zone_data && zone_data["zoneTimeDetails"]&.any?

      our_team_abbrev, opponent_team_abbrev, opponent_zone_data = fetch_opponent_data(game_id, team_id)

      post_text = format_special_teams_post(zone_data, opponent_zone_data, our_team_abbrev, opponent_team_abbrev)
      RodTheBot::Post.perform_async(post_text) if post_text
    rescue => e
      Rails.logger.error("EdgeSpecialTeamsWorker error: #{e.message}")
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

      opp_zone_data = opponent_id ? NhlApi.fetch_team_zone_time_details(opponent_id) : nil

      [our_abbrev, opp_abbrev, opp_zone_data]
    end

    def format_special_teams_post(data, opponent_data, our_team_abbrev, opponent_team_abbrev)
      pp_data = data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "pp" }
      pk_data = data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "pk" }

      return nil unless pp_data && pk_data

      our_team_abbrev ||= ENV["NHL_TEAM_ABBREVIATION"]

      post = "⚡ SPECIAL TEAMS MATCHUP\n\n"
      post += format_team_special_teams(data, pp_data, pk_data, our_team_abbrev)

      if opponent_data && opponent_team_abbrev
        opp_pp_data = opponent_data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "pp" }
        opp_pk_data = opponent_data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "pk" }
        if opp_pp_data && opp_pk_data
          post += "\n#{format_team_special_teams(opponent_data, opp_pp_data, opp_pk_data, opponent_team_abbrev)}"
        end
      end

      post
    end

    def format_team_special_teams(data, pp_data, pk_data, team_abbrev)
      pp_oz_pct = (pp_data["offensiveZonePctg"] * 100).round(1)
      pp_oz_rank = pp_data["offensiveZoneRank"]
      pk_oz_pct = (pk_data["offensiveZonePctg"] * 100).round(1)
      pk_oz_rank = pk_data["offensiveZoneRank"]

      <<~STATS
        #{team_abbrev} special teams:
        • PP: #{pp_oz_pct}% off. zone time (##{pp_oz_rank} in NHL)
        • PK: #{pk_oz_pct}% off. zone time (##{pk_oz_rank})
      STATS
    end
  end
end
