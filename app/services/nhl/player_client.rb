module Nhl
  class PlayerClient < Client
    base_uri "https://api-web.nhle.com/v1"

    class << self
      def landing(player_id)
        Rails.cache.fetch("player_landing_feed_#{player_id}", expires_in: 8.hours) do
          get_json("/player/#{player_id}/landing")
        end
      end

      def game_log(player_id, limit: 10)
        Rails.cache.fetch("player_game_log_#{player_id}_#{limit}_#{Date.current}", expires_in: 4.hours) do
          season = SeasonCalendar.current_season
          game_type = SeasonCalendar.postseason? ? 3 : 2
          get_json("/player/#{player_id}/game-log/#{season}/#{game_type}").fetch("gameLog", []).first(limit)
        end
      end

      def career_totals(player_id, season_type: :regularSeason)
        landing(player_id).dig("careerTotals", season_type.to_s) || {}
      end

      def club_stats(team_abbreviation, season: "now")
        get_json("/club-stats/#{team_abbreviation}/#{season}")
      end
    end
  end
end
