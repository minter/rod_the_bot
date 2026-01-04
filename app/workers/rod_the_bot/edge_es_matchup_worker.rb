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
      return unless post_text

      # Account for hashtags that will be added by Post worker
      hashtags = ENV["TEAM_HASHTAGS"] || ""
      hashtag_length = hashtags.empty? ? 0 : hashtags.length + 1 # +1 for newline
      max_content_length = 300 - hashtag_length

      # If post is too long, remove shot differential section
      if post_text.length > max_content_length
        post_text = format_es_matchup_post(your_zone_data, opp_zone_data, your_team_abbrev, opponent_team_abbrev, include_shot_diff: false)
      end

      RodTheBot::Post.perform_async(post_text) if post_text && post_text.length <= max_content_length
    rescue => e
      Rails.logger.error("EdgeEsMatchupWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_es_matchup_post(your_data, opp_data, your_team_abbrev, opponent_team_abbrev, include_shot_diff: true)
      your_es = your_data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "es" }
      opp_es = opp_data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "es" }

      return nil unless your_es && opp_es

      your_shot_diff = your_data["shotDifferential"] || {}
      opp_shot_diff = opp_data["shotDifferential"] || {}

      your_oz_pct = (your_es["offensiveZonePctg"] * 100).round(1)
      your_oz_rank = your_es["offensiveZoneRank"]
      your_dz_pct = (your_es["defensiveZonePctg"] * 100).round(1)
      your_dz_rank = your_es["defensiveZoneRank"]

      opp_oz_pct = (opp_es["offensiveZonePctg"] * 100).round(1)
      opp_oz_rank = opp_es["offensiveZoneRank"]
      opp_dz_pct = (opp_es["defensiveZonePctg"] * 100).round(1)
      opp_dz_rank = opp_es["defensiveZoneRank"]

      post = <<~POST
        ⚔️ 5V5 ZONE CONTROL

        #{your_team_abbrev} vs #{opponent_team_abbrev}:

        🏒 Offensive Zone Time
        • #{your_team_abbrev}: #{your_oz_pct}% (##{your_oz_rank})
        • #{opponent_team_abbrev}: #{opp_oz_pct}% (##{opp_oz_rank})

        🏒 Defensive Zone Time
        • #{your_team_abbrev}: #{your_dz_pct}% (##{your_dz_rank} least)
        • #{opponent_team_abbrev}: #{opp_dz_pct}% (##{opp_dz_rank} least)
      POST

      if include_shot_diff && your_shot_diff["shotAttemptDifferential"] && opp_shot_diff["shotAttemptDifferential"]
        your_shot_diff_val = your_shot_diff["shotAttemptDifferential"].round(1)
        your_shot_diff_rank = your_shot_diff["shotAttemptDifferentialRank"]
        opp_shot_diff_val = opp_shot_diff["shotAttemptDifferential"].round(1)
        opp_shot_diff_rank = opp_shot_diff["shotAttemptDifferentialRank"]

        your_sign = your_shot_diff_val >= 0 ? "+" : ""
        opp_sign = opp_shot_diff_val >= 0 ? "+" : ""

        post += <<~POST

          🏒 Shot Differential
          • #{your_team_abbrev}: #{your_sign}#{your_shot_diff_val} per game (##{your_shot_diff_rank})
          • #{opponent_team_abbrev}: #{opp_sign}#{opp_shot_diff_val} per game (##{opp_shot_diff_rank})
        POST
      end

      post
    end
  end
end

