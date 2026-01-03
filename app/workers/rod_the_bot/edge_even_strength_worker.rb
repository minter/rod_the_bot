module RodTheBot
  class EdgeEvenStrengthWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    def perform(game_id = nil)
      return if NhlApi.preseason?

      # Get team ID from environment
      team_id = ENV["NHL_TEAM_ID"].to_i

      # Fetch team zone time data (already has ES breakdown)
      zone_data = NhlApi.fetch_team_zone_time_details(team_id)
      return unless zone_data && zone_data["zoneTimeDetails"]&.any?

      # Format and post
      post_text = format_even_strength_post(zone_data)
      RodTheBot::Post.perform_async(post_text) if post_text
    rescue => e
      Rails.logger.error("EdgeEvenStrengthWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_even_strength_post(data)
      es_data = data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "es" }
      return nil unless es_data

      es_oz_pct = (es_data["offensiveZonePctg"] * 100).round(1)
      es_oz_rank = es_data["offensiveZoneRank"]
      es_dz_pct = (es_data["defensiveZonePctg"] * 100).round(1)
      es_dz_rank = es_data["defensiveZoneRank"]

      shot_diff = data["shotDifferential"] || {}
      shot_diff_val = shot_diff["shotAttemptDifferential"]&.round(1)
      shot_diff_rank = shot_diff["shotAttemptDifferentialRank"]

      post = <<~POST
        ⚡ EVEN STRENGTH EDGE

        Hurricanes 5v5 zone control:

        🏒 Offensive Zone Time
        • #{es_oz_pct}% (##{es_oz_rank} in NHL)

        🏒 Defensive Zone Time
        • #{es_dz_pct}% (##{es_dz_rank} least)
      POST

      if shot_diff_val && shot_diff_rank
        post += "        • +#{shot_diff_val} shot differential per game (##{shot_diff_rank})\n"
      end

      post
    end
  end
end

