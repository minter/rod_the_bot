module RodTheBot
  class EdgeTeamShotSpeedWorker
    include Sidekiq::Worker

    def perform(_game_id = nil)
      return if NhlApi.preseason?

      # Get team ID from environment
      team_id = ENV["NHL_TEAM_ID"].to_i

      # Fetch team shot speed data
      shot_data = NhlApi.fetch_team_shot_speed_detail(team_id)
      return unless shot_data && shot_data["shotSpeedDetails"]&.any?

      # Format and post
      post_text = format_team_shot_speed_post(shot_data)
      RodTheBot::Post.perform_async(post_text) if post_text
    rescue => e
      Rails.logger.error("EdgeTeamShotSpeedWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_team_shot_speed_post(data)
      all_positions = data["shotSpeedDetails"]&.find { |d| d["position"] == "all" }
      return nil unless all_positions

      top_shot_speed = all_positions["topShotSpeed"]
      avg_shot_speed = all_positions["avgShotSpeed"]

      return nil unless top_shot_speed && avg_shot_speed

      top_speed_val = top_shot_speed["imperial"]&.round(2)
      top_speed_rank = top_shot_speed["rank"]
      avg_speed_val = avg_shot_speed["imperial"]&.round(2)
      avg_speed_rank = avg_shot_speed["rank"]

      # Get hardest shot player name if available
      hardest_shot_player = data["hardestShots"]&.first
      player_name = if hardest_shot_player && hardest_shot_player["player"]
        "#{hardest_shot_player["player"]["firstName"]["default"]} #{hardest_shot_player["player"]["lastName"]["default"]}"
      else
        nil
      end

      team_abbrev = ENV["NHL_TEAM_ABBREVIATION"]
      post = <<~POST
        🎯 SHOT SPEED PREVIEW

        #{team_abbrev} shot speed:

        • Average: #{avg_speed_val} mph (##{avg_speed_rank} in NHL)
        • Hardest: #{top_speed_val} mph (##{top_speed_rank})
      POST

      if player_name
        post += "        • Hardest shot: #{player_name}\n"
      end

      post
    end
  end
end

