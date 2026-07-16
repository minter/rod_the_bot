module RodTheBot
  module ScoringChange
    class Detector
      Result = Data.define(:status, :play, :challenge)

      def initialize(feed)
        @feed = feed
      end

      def detect(play_id:, original_play:)
        play = feed.fetch("plays", []).find { |candidate| candidate["eventId"].to_s == play_id.to_s }
        return Result.new(status: :overturned, play: nil, challenge: nearby_challenge(original_play)) unless play
        return Result.new(status: :unchanged, play: play, challenge: nil) unless play["typeDescKey"] == "goal"

        status = (participants(play) == participants(original_play)) ? :unchanged : :corrected
        Result.new(status: status, play: play, challenge: nil)
      end

      private

      attr_reader :feed

      def participants(play)
        details = play.fetch("details", {})
        %w[scoringPlayerId assist1PlayerId assist2PlayerId].map { |key| details[key]&.to_s }
      end

      def nearby_challenge(goal)
        period = goal.dig("periodDescriptor", "number")
        goal_time = minutes(goal["timeInPeriod"])
        feed.fetch("plays", []).find do |play|
          play["typeDescKey"] == "stoppage" && play.dig("details", "reason")&.include?("chlg") &&
            play.dig("periodDescriptor", "number") == period &&
            (minutes(play["timeInPeriod"]) - goal_time).abs <= 3
        end
      end

      def minutes(value)
        minutes, seconds = value.to_s.split(":").map(&:to_i)
        minutes + seconds / 60.0
      end
    end
  end
end
