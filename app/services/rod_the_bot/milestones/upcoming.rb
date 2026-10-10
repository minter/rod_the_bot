module RodTheBot
  module Milestones
    class Upcoming
      Entry = Data.define(:player_id, :type, :target, :remaining)

      # Career-total stat and how close a player must be for each milestone type
      # to be worth announcing before a game.
      SKATER_STATS = {
        "goal" => ["goals", 3],
        "assist" => ["assists", 5],
        "point" => ["points", 6],
        "game" => ["gamesPlayed", 2]
      }.freeze
      GOALIE_STATS = {
        "win" => ["wins", 2],
        "shutout" => ["shutouts", 1],
        "game" => ["gamesPlayed", 2]
      }.freeze

      def initialize(career_totals:)
        @career_totals = career_totals
      end

      def for(player_id, goalie:)
        totals = career_totals.call(player_id)
        (goalie ? GOALIE_STATS : SKATER_STATS).filter_map do |type, (stat, reach)|
          current = totals.fetch(stat, 0).to_i
          target = next_target(type, current)
          next unless target

          remaining = target - current
          Entry.new(player_id: player_id, type: type, target: target, remaining: remaining) if remaining <= reach
        end
      end

      private

      attr_reader :career_totals

      # First-career milestones are announced when they happen, not previewed.
      def next_target(type, current)
        Thresholds::VALUES.fetch(type).find { |value| value > 1 && value > current }
      end
    end
  end
end
