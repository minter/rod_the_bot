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
      skater_skating_distance_detail: ["skater-skating-distance-detail", 8.hours]
    }.freeze

    class << self
      ENDPOINTS.each do |name, (path, ttl)|
        define_method("fetch_#{name}") do |subject_id, season: nil, game_type: nil|
          period = (season && game_type) ? "#{season}/#{game_type}" : "now"
          cache_key = "edge_#{name}_#{subject_id}_#{period.tr("/", "_")}"
          Rails.cache.fetch(cache_key, expires_in: ttl) { get_json("/edge/#{path}/#{subject_id}/#{period}") }
        end
      end
    end
  end
end
