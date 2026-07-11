module RodTheBot
  module GoalieChange
    class Detector
      Result = Data.define(:status, :goalie_id, :previous_goalie_id)

      def initialize(redis: REDIS)
        @redis = redis
      end

      def detect(game_id:, team_id:, goalie_id:, event_id:, plays:)
        goalie_id = goalie_id.to_s
        state_key = "game:#{game_id}:current_goalie:#{team_id}"
        current = @redis.get(state_key)
        if current.blank?
          @redis.set(state_key, goalie_id, ex: 28800)
          return Result.new(status: :initialized, goalie_id: goalie_id, previous_goalie_id: nil)
        end
        return Result.new(status: :unchanged, goalie_id: goalie_id, previous_goalie_id: current) if current == goalie_id

        recent = plays.count { |play| play.dig("details", "goalieInNetId").to_s == goalie_id && play["eventId"] < event_id }
        if recent >= 3
          @redis.set(state_key, goalie_id, ex: 28800)
          return Result.new(status: :stale_cache, goalie_id: goalie_id, previous_goalie_id: current)
        end

        lock = "game:#{game_id}:goalie_change_lock:#{team_id}:#{goalie_id}"
        return Result.new(status: :claimed, goalie_id: goalie_id, previous_goalie_id: current) unless @redis.set(lock, "claimed", nx: true, ex: 300)

        Result.new(status: :changed, goalie_id: goalie_id, previous_goalie_id: current)
      end

      def commit(game_id:, team_id:, goalie_id:)
        @redis.set("game:#{game_id}:current_goalie:#{team_id}", goalie_id.to_s, ex: 28800)
      end
    end
  end
end
