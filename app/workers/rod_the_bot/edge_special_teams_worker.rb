module RodTheBot
  class EdgeSpecialTeamsWorker
    include Sidekiq::Worker

    def perform(_game_id = nil)
      return if NhlApi.preseason?

      # Get team ID from environment
      team_id = ENV["NHL_TEAM_ID"].to_i

      # Fetch team zone time data (already has PP/PK breakdowns)
      zone_data = NhlApi.fetch_team_zone_time_details(team_id)
      return unless zone_data && zone_data["zoneTimeDetails"]&.any?

      # Format and post
      post_text = format_special_teams_post(zone_data)
      RodTheBot::Post.perform_async(post_text) if post_text
    rescue => e
      Rails.logger.error("EdgeSpecialTeamsWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_special_teams_post(data)
      pp_data = data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "pp" }
      pk_data = data["zoneTimeDetails"]&.find { |d| d["strengthCode"] == "pk" }

      return nil unless pp_data && pk_data

      team_abbrev = ENV["NHL_TEAM_ABBREVIATION"]
      pp_oz_pct = (pp_data["offensiveZonePctg"] * 100).round(1)
      pp_oz_rank = pp_data["offensiveZoneRank"]
      pk_oz_pct = (pk_data["offensiveZonePctg"] * 100).round(1)
      pk_oz_rank = pk_data["offensiveZoneRank"]

      <<~POST
        ⚡ SPECIAL TEAMS EDGE

        #{team_abbrev} special teams zone control:

        🏒 Power Play
        • #{pp_oz_pct}% offensive zone time (##{pp_oz_rank} in NHL)

        🏒 Penalty Kill
        • #{pk_oz_pct}% offensive zone time (##{pk_oz_rank})
      POST
    end
  end
end
