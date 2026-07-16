module RodTheBot
  module Goal
    class Situation
      def initialize(code, scoring_team_id:, home_id:, away_id:)
        @code = code
        away_goalies, away_skaters, home_skaters, home_goalies = code.chars.map(&:to_i)
        away_players = away_goalies + away_skaters
        home_players = home_goalies + home_skaters
        @scoring_players, @opposing_players, @opposing_goalies = (scoring_team_id.to_i == home_id.to_i) ? [home_players, away_players, away_goalies] : [away_players, home_players, home_goalies]
      end

      def penalty_shot?
        code.chars.map(&:to_i).then { |away_goalies, away_skaters, home_skaters, home_goalies| away_goalies + away_skaters == 1 && home_goalies + home_skaters == 1 }
      end

      def modifiers
        values = if penalty_shot?
          ["Penalty Shot"]
        else
          [].tap do |items|
            items << "Shorthanded" if scoring_players < opposing_players
            items << "Power Play" if scoring_players > opposing_players
            items << "Empty Net" if opposing_goalies.zero?
          end
        end
        values.empty? ? "" : " #{values.join(", ")}"
      end

      private

      attr_reader :code, :scoring_players, :opposing_players, :opposing_goalies
    end
  end
end
