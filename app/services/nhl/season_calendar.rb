module Nhl
  class SeasonCalendar < Client
    base_uri "https://api-web.nhle.com/v1"

    class << self
      def current_season
        get_json("/season").last.to_s
      end

      def postseason?(today: local_today)
        today > Date.parse(schedule["regularSeasonEndDate"])
      end

      def preseason?(today: local_today)
        today >= Date.parse(schedule["preSeasonStartDate"]) &&
          today < Date.parse(schedule["regularSeasonStartDate"])
      end

      def offseason?(today: local_today)
        preseason_start = Date.parse(schedule["preSeasonStartDate"])
        playoff_end = Date.parse(schedule["playoffEndDate"])
        today < preseason_start || today > playoff_end || schedule["numberOfGames"].zero?
      end

      private

      def schedule
        Rails.cache.fetch("league_schedule_now", expires_in: 3.hours) { get_json("/schedule/now") }
      end

      def local_today
        Time.use_zone(ENV.fetch("TIME_ZONE")) { Time.zone.today }
      end
    end
  end
end
