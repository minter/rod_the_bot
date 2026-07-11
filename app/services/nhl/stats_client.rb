module Nhl
  class StatsClient < Client
    base_uri "https://api.nhle.com/stats/rest/en"

    class << self
      def teams
        Rails.cache.fetch("teams", expires_in: 30.days) do
          get_json("/team").fetch("data", []).to_h do |team|
            team = team.deep_symbolize_keys
            [team[:id], team]
          end
        end
      end

      def skater_milestones
        cached("skater_milestones_#{Date.current}", 24.hours) { get_json("/milestones/skaters") }
      rescue RequestError
        {}
      end

      def goalie_milestones
        cached("goalie_milestones_#{Date.current}", 24.hours) { get_json("/milestones/goalies") }
      rescue RequestError
        {}
      end

      def player_career_stats(player_id)
        cached("player_career_stats_#{player_id}", 1.hour) do
          get_json("/skater/stats?cayenneExp=playerId=#{player_id}")
        end
      rescue RequestError
        {}
      end

      private

      def cached(key, expires_in, &block)
        Rails.cache.fetch(key, expires_in: expires_in, &block)
      end
    end
  end
end
