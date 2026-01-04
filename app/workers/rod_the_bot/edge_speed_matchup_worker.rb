module RodTheBot
  class EdgeSpeedMatchupWorker
    include Sidekiq::Worker

    def perform(game_id)
      return if NhlApi.preseason?

      your_team_id = ENV["NHL_TEAM_ID"].to_i
      opponent_team_id = NhlApi.opponent_team_id(game_id)
      return unless opponent_team_id

      # Fetch data for both teams
      your_speed_data = NhlApi.fetch_team_skating_speed_detail(your_team_id)
      opp_speed_data = NhlApi.fetch_team_skating_speed_detail(opponent_team_id)

      return unless your_speed_data && opp_speed_data

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
      post_text = format_speed_matchup_post(your_speed_data, opp_speed_data, your_team_abbrev, opponent_team_abbrev)
      return unless post_text

      # Account for hashtags that will be added by Post worker
      hashtags = ENV["TEAM_HASHTAGS"] || ""
      hashtag_length = hashtags.empty? ? 0 : hashtags.length + 1 # +1 for newline
      max_content_length = 300 - hashtag_length

      # If post is too long, simplify it
      if post_text.length > max_content_length
        post_text = format_speed_matchup_post(your_speed_data, opp_speed_data, your_team_abbrev, opponent_team_abbrev, include_bursts: false)
      end

      RodTheBot::Post.perform_async(post_text) if post_text && post_text.length <= max_content_length
    rescue => e
      Rails.logger.error("EdgeSpeedMatchupWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_speed_matchup_post(your_data, opp_data, your_team_abbrev, opponent_team_abbrev, include_bursts: true)
      your_all = your_data["skatingSpeedDetails"]&.find { |d| d["positionCode"] == "all" }
      opp_all = opp_data["skatingSpeedDetails"]&.find { |d| d["positionCode"] == "all" }

      return nil unless your_all && opp_all

      your_max_speed = your_all["maxSkatingSpeed"]
      opp_max_speed = opp_all["maxSkatingSpeed"]
      your_bursts_over_22 = your_all["burstsOver22"]
      opp_bursts_over_22 = opp_all["burstsOver22"]

      return nil unless your_max_speed && opp_max_speed && your_bursts_over_22 && opp_bursts_over_22

      your_max_speed_val = your_max_speed["imperial"]&.round(2)
      your_max_speed_rank = your_max_speed["rank"]
      opp_max_speed_val = opp_max_speed["imperial"]&.round(2)
      opp_max_speed_rank = opp_max_speed["rank"]

      your_bursts_val = your_bursts_over_22["value"]
      your_bursts_rank = your_bursts_over_22["rank"]
      opp_bursts_val = opp_bursts_over_22["value"]
      opp_bursts_rank = opp_bursts_over_22["rank"]

      post = <<~POST
        💨 SPEED MATCHUP

        #{your_team_abbrev} vs #{opponent_team_abbrev}:

        🏒 Top Speed
        • #{your_team_abbrev}: #{your_max_speed_val} mph (##{your_max_speed_rank})
        • #{opponent_team_abbrev}: #{opp_max_speed_val} mph (##{opp_max_speed_rank})
      POST

      if include_bursts
        post += <<~POST

          🏒 Bursts Over 22 mph
          • #{your_team_abbrev}: #{your_bursts_val} (##{your_bursts_rank})
          • #{opponent_team_abbrev}: #{opp_bursts_val} (##{opp_bursts_rank})
        POST
      end

      post
    end
  end
end
