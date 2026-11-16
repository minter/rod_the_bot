module Nhl
  class EdgeClient < Client
    base_uri "https://api-web.nhle.com/v1"

    ENDPOINTS = {
      team_zone_time_details: ["team-zone-time-details", 6.hours],
      team_skating_speed_detail: ["team-skating-speed-detail", 6.hours],
      team_shot_speed_detail: ["team-shot-speed-detail", 6.hours],
      skater_zone_time: ["skater-zone-time", 8.hours],
      skater_skating_speed_detail: ["skater-skating-speed-detail", 8.hours],
      goalie_detail: ["goalie-detail", 8.hours],
      skater_shot_location_detail: ["skater-shot-location-detail", 8.hours],
      skater_skating_distance_detail: ["skater-skating-distance-detail", 8.hours],
      team_skating_distance_detail: ["team-skating-distance-detail", 6.hours]
    }.freeze

    class << self
      # fresh: true skips a cached response, for callers waiting on data the NHL has not published yet.
      ENDPOINTS.each do |name, (path, ttl)|
        define_method("fetch_#{name}") do |subject_id, season: nil, game_type: nil, game_id: nil, fresh: false|
          if game_id
            context = GameId.new(game_id)
            season ||= context.season
            game_type ||= context.game_type
          end

          period = (season && game_type) ? "#{season}/#{game_type}" : "now"
          cache_key = "edge_#{name}_#{subject_id}_#{period.tr("/", "_")}"
          Rails.cache.fetch(cache_key, expires_in: ttl, force: fresh) { get_json("/edge/#{path}/#{subject_id}/#{period}") }
        rescue RequestError => e
          raise unless period != "now" && e.message.end_with?("HTTP 404")

          Rails.logger.warn "EDGE data unavailable for #{path}/#{subject_id}/#{period}"
          nil
        end
      end
    end
  end
end
