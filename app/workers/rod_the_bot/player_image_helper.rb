module RodTheBot
  module PlayerImageHelper
    def fetch_player_headshot(player_id)
      return nil unless player_id

      player_feed = NhlApi.fetch_player_landing_feed(player_id)
      headshot = player_feed&.dig("headshot")

      if headshot.nil?
        Rails.logger.warn("#{self.class.name}: No headshot found for player #{player_id}")
      end

      headshot
    rescue => e
      Rails.logger.error("#{self.class.name}: Error fetching headshot for player #{player_id}: #{e.message}")
      nil
    end

    def fetch_player_headshots(player_ids)
      player_ids.compact.filter_map { |id| fetch_player_headshot(id) }
    end
  end
end
