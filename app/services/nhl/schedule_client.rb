module Nhl
  class ScheduleClient < Client
    base_uri "https://api-web.nhle.com/v1"

    class << self
      def team_schedule(date: Date.current, team_abbreviation: ENV.fetch("NHL_TEAM_ABBREVIATION"))
        date = date.to_s
        Rails.cache.fetch("team_schedule_#{team_abbreviation}_#{date}", expires_in: 12.hours) do
          get_json("/club-schedule/#{team_abbreviation}/week/#{date}")
        end
      end

      def league_schedule(date: Date.current)
        date = date.to_s
        Rails.cache.fetch("league_schedule_#{date}", expires_in: 3.hours) do
          get_json("/schedule/#{date}")
        end
      end

      def scores(date: Date.yesterday)
        date = date.to_s
        Rails.cache.fetch("scores_#{date}", expires_in: 18.hours) do
          games = get_json("/score/#{date}")["games"] || []
          games.select { |game| game["gameDate"] == date }
        end
      end

      def postseason_carousel
        get_json("/playoff-series/carousel/#{SeasonCalendar.current_season}/")
      rescue RequestError
        nil
      end

      def todays_game(date: Date.current, team_abbreviation: ENV.fetch("NHL_TEAM_ABBREVIATION"))
        date = date.to_s
        games = team_schedule(date: date, team_abbreviation: team_abbreviation)["games"] || []
        games.find { |game| game["gameDate"] == date }
      end
    end
  end
end
