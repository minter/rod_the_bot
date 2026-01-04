module RodTheBot
  class EdgeShotSpeedMatchupWorker
    include Sidekiq::Worker

    def perform(game_id)
      return if NhlApi.preseason?

      your_team_id = ENV["NHL_TEAM_ID"].to_i
      opponent_team_id = NhlApi.opponent_team_id(game_id)
      return unless opponent_team_id

      # Fetch data for both teams
      your_shot_data = NhlApi.fetch_team_shot_speed_detail(your_team_id)
      opp_shot_data = NhlApi.fetch_team_shot_speed_detail(opponent_team_id)

      return unless your_shot_data && opp_shot_data

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
      post_text = format_shot_speed_matchup_post(your_shot_data, opp_shot_data, your_team_abbrev, opponent_team_abbrev)
      return unless post_text

      # Account for hashtags that will be added by Post worker
      hashtags = ENV["TEAM_HASHTAGS"] || ""
      hashtag_length = hashtags.empty? ? 0 : hashtags.length + 1 # +1 for newline
      max_content_length = 300 - hashtag_length

      RodTheBot::Post.perform_async(post_text) if post_text && post_text.length <= max_content_length
    rescue => e
      Rails.logger.error("EdgeShotSpeedMatchupWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_shot_speed_matchup_post(your_data, opp_data, your_team_abbrev, opponent_team_abbrev)
      your_all = your_data["shotSpeedDetails"]&.find { |d| d["position"] == "all" }
      opp_all = opp_data["shotSpeedDetails"]&.find { |d| d["position"] == "all" }

      return nil unless your_all && opp_all

      your_avg_speed = your_all["avgShotSpeed"]
      opp_avg_speed = opp_all["avgShotSpeed"]
      your_top_speed = your_all["topShotSpeed"]
      opp_top_speed = opp_all["topShotSpeed"]

      return nil unless your_avg_speed && opp_avg_speed && your_top_speed && opp_top_speed

      your_avg_val = your_avg_speed["imperial"]&.round(2)
      your_avg_rank = your_avg_speed["rank"]
      opp_avg_val = opp_avg_speed["imperial"]&.round(2)
      opp_avg_rank = opp_avg_speed["rank"]

      your_top_val = your_top_speed["imperial"]&.round(2)
      your_top_rank = your_top_speed["rank"]
      opp_top_val = opp_top_speed["imperial"]&.round(2)
      opp_top_rank = opp_top_speed["rank"]

      <<~POST
        🎯 SHOT SPEED MATCHUP

        #{your_team_abbrev} vs #{opponent_team_abbrev}:

        🏒 Average Shot Speed
        • #{your_team_abbrev}: #{your_avg_val} mph (##{your_avg_rank})
        • #{opponent_team_abbrev}: #{opp_avg_val} mph (##{opp_avg_rank})

        🏒 Hardest Shot
        • #{your_team_abbrev}: #{your_top_val} mph (##{your_top_rank})
        • #{opponent_team_abbrev}: #{opp_top_val} mph (##{opp_top_rank})
      POST
    end
  end
end
