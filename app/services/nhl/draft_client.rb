module Nhl
  class DraftClient < Client
    base_uri "https://api-web.nhle.com/v1"

    class << self
      def picks(year)
        get_json("/draft/picks/#{year}/all")
      end

      def rankings(year)
        Rails.cache.fetch("draft_rankings_#{year}", expires_in: 24.hours) do
          {
            north_american_skaters: ranking_group(year, 1),
            international_skaters: ranking_group(year, 2),
            north_american_goalies: ranking_group(year, 3),
            international_goalies: ranking_group(year, 4)
          }
        end
      end

      private

      def ranking_group(year, category)
        get_json("/draft/rankings/#{year}/#{category}")["rankings"]
      end
    end
  end
end
