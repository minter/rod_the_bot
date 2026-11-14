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

      def team_summary(season:, game_type:, sort:)
        query = URI.encode_www_form(
          sort: sort,
          cayenneExp: "seasonId=#{season} and gameTypeId=#{game_type}"
        )
        get_json("/team/summary?#{query}").fetch("data", [])
      end

      def shift_charts(game_id)
        cached("shift_charts_#{game_id}", 1.hour) do
          query = URI.encode_www_form(cayenneExp: "gameId=#{game_id}")
          get_json("/shiftcharts?#{query}").fetch("data", [])
        end
      end

      # Season-to-date records by game situation, keyed by situation with
      # {wins:, losses:, ot_losses:} values. Situations the NHL has not reported are absent.
      def team_situational_records(team_id:, season:, game_type:)
        cached("team_situational_records_#{team_id}_#{season}_#{game_type}", 6.hours) do
          filter = "seasonId=#{season} and gameTypeId=#{game_type} and teamId=#{team_id}"
          normalize_situational_records(team_report("leadingtrailing", filter), team_report("scoretrailfirst", filter))
        end
      end

      private

      def team_report(report, filter)
        get_json("/team/#{report}?#{URI.encode_www_form(cayenneExp: filter)}").fetch("data", []).first
      end

      def normalize_situational_records(by_period, by_first_goal)
        records = {}
        if by_period
          [1, 2].each do |period|
            records[:"leading_after_#{period}"] = record(by_period, "winsLeadPeriod#{period}", "lossLeadPeriod#{period}", "otLossLeadPeriod#{period}")
            records[:"trailing_after_#{period}"] = record(by_period, "winsTrailPeriod#{period}", "lossTrailPeriod#{period}", "otLossTrailPeriod#{period}")
          end
        end
        if by_first_goal
          records[:scoring_first] = record(by_first_goal, "winsScoringFirst", "lossesScoringFirst", "otLossesScoringFirst")
          records[:trailing_first] = record(by_first_goal, "winsTrailingFirst", "lossesTrailingFirst", "otLossesTrailingFirst")
        end
        # The NHL does not report tied-after-period records, so derive them from the overall
        # record, but only when both reports cover the same games.
        if by_period && by_first_goal && by_period["gamesPlayed"] == by_first_goal["gamesPlayed"]
          overall = record(by_first_goal, "wins", "losses", "otLosses")
          [1, 2].each do |period|
            records[:"tied_after_#{period}"] = overall.to_h do |result, total|
              [result, total - records[:"leading_after_#{period}"][result] - records[:"trailing_after_#{period}"][result]]
            end
          end
        end
        records
      end

      def record(row, wins, losses, ot_losses)
        {wins: row[wins].to_i, losses: row[losses].to_i, ot_losses: row[ot_losses].to_i}
      end

      def cached(key, expires_in, &block)
        Rails.cache.fetch(key, expires_in: expires_in, &block)
      end
    end
  end
end
