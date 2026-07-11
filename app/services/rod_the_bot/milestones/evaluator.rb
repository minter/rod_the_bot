module RodTheBot
  module Milestones
    class Evaluator
      Event = Data.define(:type, :value, :first)

      def initialize(totals:)
        @totals = totals
      end

      def scorer(player_id)
        goals = total(player_id, "goals")
        points = total(player_id, "points")
        events = []
        events << Event.new(type: "goal", value: goals, first: goals == 1 && points == 1) if Thresholds.include?("goal", goals)
        events << Event.new(type: "point", value: points, first: points == 1) if Thresholds.include?("point", points) && goals != 1
        events
      end

      def assister(player_id)
        assists = total(player_id, "assists")
        points = total(player_id, "points")
        events = []
        events << Event.new(type: "assist", value: assists, first: false) if Thresholds.include?("assist", assists)
        events << Event.new(type: "point", value: points, first: points == 1) if Thresholds.include?("point", points)
        events
      end

      def goalie(player_id)
        %w[win shutout].filter_map do |type|
          value = total(player_id, "#{type}s")
          Event.new(type: type, value: value, first: value == 1) if Thresholds.include?(type, value)
        end
      end

      private

      attr_reader :totals

      def total(player_id, stat)
        totals.for(player_id, stat)
      end
    end
  end
end
