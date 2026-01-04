module RodTheBot
  class EdgeEsMatchupWorker
    include Sidekiq::Worker

    def perform(game_id)
      return if NhlApi.preseason?

      your_team_id = ENV["NHL_TEAM_ID"].to_i
      opponent_team_id = NhlApi.opponent_team_id(game_id)
      return unless opponent_team_id

      # Fetch data for both teams
      your_zone_data = NhlApi.fetch_team_zone_time_details(your_team_id)
      opp_zone_data = NhlApi.fetch_team_zone_time_details(opponent_team_id)

      return unless your_zone_data && opp_zone_data

      # Get team abbreviations from game feed
      feed = NhlApi.fetch_landing_feed(game_id)
      return unless feed

      home_id = feed.dig("homeTeam", "id").to_i
      your_team_abbrev = if home_id == your_team_id
        feed.dig("homeTeam", "abbrev")
      else
        feed.dig("awayTeam", "abbrev")
      end

      opponent_team_abbrev = if home_id == opponent_team_id
        feed.dig("homeTeam", "abbrev")
      else
        feed.dig("awayTeam", "abbrev")
      end

      # Format and post
      post_text = format_es_matchup_post(your_zone_data, opp_zone_data, your_team_abbrev, opponent_team_abbrev)
      RodTheBot::Post.perform_async(post_text) if post_text
    rescue => e
      Rails.logger.error("EdgeEsMatchupWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_es_matchup_post(your_data, opp_data, your_team_abbrev, opponent_team_abbrev)
      your_es = your_data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "es" }
      opp_es = opp_data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "es" }

      return nil unless your_es && opp_es

      your_oz_pct = (your_es["offensiveZonePctg"] * 100).round(1)
      your_oz_rank = your_es["offensiveZoneRank"]
      your_dz_pct = (your_es["defensiveZonePctg"] * 100).round(1)
      your_dz_rank = your_es["defensiveZoneRank"]

      opp_oz_pct = (opp_es["offensiveZonePctg"] * 100).round(1)
      opp_oz_rank = opp_es["offensiveZoneRank"]
      opp_dz_pct = (opp_es["defensiveZonePctg"] * 100).round(1)
      opp_dz_rank = opp_es["defensiveZoneRank"]

      <<~POST
        ⚔️ 5V5 ZONE CONTROL

        #{your_team_abbrev} vs #{opponent_team_abbrev}:

        🏒 Offensive Zone Time
        • #{your_team_abbrev}: #{your_oz_pct}% (##{your_oz_rank})
        • #{opponent_team_abbrev}: #{opp_oz_pct}% (##{opp_oz_rank})

        🏒 Defensive Zone Time
        • #{your_team_abbrev}: #{your_dz_pct}% (##{your_dz_rank} least)
        • #{opponent_team_abbrev}: #{opp_dz_pct}% (##{opp_dz_rank} least)
      POST
    end
  end
end

