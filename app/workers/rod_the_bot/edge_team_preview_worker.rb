module RodTheBot
  class EdgeTeamPreviewWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    def perform(game_id = nil)
      return if NhlApi.preseason?

      # Get team ID from environment
      team_id = ENV["NHL_TEAM_ID"].to_i

      # Fetch team zone time data
      zone_data = NhlApi.fetch_team_zone_time_details(team_id)
      return unless zone_data && zone_data["zoneTimeDetails"]&.any?

      # Format and post
      post_text = format_team_zone_time_post(zone_data)
      RodTheBot::Post.perform_async(post_text) if post_text
    rescue => e
      Rails.logger.error("EdgeTeamPreviewWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_team_zone_time_post(data)
      all_situations = data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "all" }
      return nil unless all_situations

      shot_diff = data["shotDifferential"] || {}

      oz_pct = (all_situations["offensiveZonePctg"] * 100).round(1)
      oz_rank = all_situations["offensiveZoneRank"]
      dz_pct = (all_situations["defensiveZonePctg"] * 100).round(1)
      dz_rank = all_situations["defensiveZoneRank"]

      shot_diff_val = shot_diff["shotAttemptDifferential"]&.round(1)
      shot_diff_rank = shot_diff["shotAttemptDifferentialRank"]

      post = <<~POST
        ⚡ BY THE NUMBERS ⚡

        Hurricanes zone control:

        🏒 Zone Dominance
        • #{oz_pct}% offensive zone time (##{oz_rank} in NHL)
        • #{dz_pct}% defensive zone time (##{dz_rank} least)
      POST

      if shot_diff_val && shot_diff_rank
        post += "        • +#{shot_diff_val} shot differential per game (##{shot_diff_rank})\n"
      end

      post
    end
  end
end
