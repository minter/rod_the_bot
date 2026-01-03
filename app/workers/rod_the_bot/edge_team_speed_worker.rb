module RodTheBot
  class EdgeTeamSpeedWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    def perform(game_id = nil)
      return if NhlApi.preseason?

      # Get team ID from environment
      team_id = ENV["NHL_TEAM_ID"].to_i

      # Fetch team speed data
      speed_data = NhlApi.fetch_team_skating_speed_detail(team_id)
      return unless speed_data && speed_data["skatingSpeedDetails"]&.any?

      # Format and post
      post_text = format_team_speed_post(speed_data)
      RodTheBot::Post.perform_async(post_text) if post_text
    rescue => e
      Rails.logger.error("EdgeTeamSpeedWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_team_speed_post(data)
      all_positions = data["skatingSpeedDetails"]&.find { |d| d["positionCode"] == "all" }
      return nil unless all_positions

      max_speed = all_positions["maxSkatingSpeed"]
      bursts_over_22 = all_positions["burstsOver22"]
      bursts_20_to_22 = all_positions["bursts20To22"]

      return nil unless max_speed && bursts_over_22 && bursts_20_to_22

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

      post = <<~POST
        💨 TEAM SPEED PREVIEW

        Hurricanes speed rankings:

        • Top speed: #{max_speed_val} mph (##{max_speed_rank} in NHL)
      POST

      if player_name
        post += "        • Fastest: #{player_name}\n"
      end

      post += <<~POST
        • #{bursts_over_22_val} bursts over 22 mph (##{bursts_over_22_rank})
        • #{bursts_20_to_22_val} bursts 20-22 mph (##{bursts_20_to_22_rank})
      POST

      post
    end
  end
end

