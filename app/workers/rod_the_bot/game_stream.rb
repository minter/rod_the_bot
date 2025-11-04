module RodTheBot
  class GameStream
    include Sidekiq::Worker
    include RodTheBot::PlayerFormatter

    attr_reader :feed, :game_id

    def perform(game_id)
      @game_id = game_id
      @feed = NhlApi.fetch_pbp_feed(game_id)
      game_final = @feed["plays"].find { |play| play["typeDescKey"] == "game-end" }.present?

      @feed["plays"].each do |play|
        process_play(play)
      end

      if game_final
        RodTheBot::FinalScoreWorker.perform_in(60, game_id)
        RodTheBot::ThreeStarsWorker.perform_in(90, game_id)
        # Disabling due to this data not appearing to be available in the API
        # RodTheBot::ThreeMinuteRecapWorker.perform_in(600, game_id)
      else
        RodTheBot::GameStream.perform_in(30, game_id)
      end
    end

    private

    def process_play(play)
      worker_class, delay = worker_mapping[play["typeDescKey"]]

      return unless worker_class

      # For goals, we only mark as processed after GoalWorker successfully posts
      # Use "completed" key instead of immediate marking to allow retries on failure
      redis_key = if play["typeDescKey"] == "goal"
        "#{game_id}:goal:completed:#{play["eventId"]}"
      else
        "#{game_id}:#{play["eventId"]}"
      end

      if play["typeDescKey"] == "goal"
        already_completed = REDIS.get(redis_key).present?
        scheduled_key = "#{game_id}:goal:scheduled:#{play["eventId"]}"
        already_scheduled = REDIS.get(scheduled_key).present?
        Rails.logger.info "GameStream: Found goal event #{play["eventId"]} for game #{game_id}. Already completed: #{already_completed}, Already scheduled: #{already_scheduled}, worker_class: #{worker_class.inspect}"
      end

      if REDIS.get(redis_key).nil?
        # For goals, use a temporary "scheduled" key to prevent duplicate scheduling
        # This expires after 5 minutes (enough time for the 90s delay + processing)
        if play["typeDescKey"] == "goal"
          scheduled_key = "#{game_id}:goal:scheduled:#{play["eventId"]}"
          if REDIS.get(scheduled_key).nil?
            worker_class.perform_in(delay, game_id, play)
            REDIS.set(scheduled_key, "true", ex: 300) # 5 minutes
          end
        else
          worker_class.perform_in(delay, game_id, play)
          REDIS.set(redis_key, "true", ex: 172800)
        end

        # Schedule milestone check with delay to allow NHL API stats to update (only during regular season and playoffs)
        schedule_milestone_check(play) unless NhlApi.preseason?
      end
    end

    def schedule_milestone_check(play)
      # Schedule milestone check immediately since we calculate from pre-game stats
      # Use a unique Redis key to prevent duplicate milestone checks
      milestone_key = "#{game_id}:milestone:#{play["eventId"]}"

      if REDIS.get(milestone_key).nil?
        # Check immediately (30 seconds after the play) using pre-game stats + in-game calculation
        RodTheBot::MilestoneCheckerWorker.perform_in(30, game_id, play)
        REDIS.set(milestone_key, "true", ex: 172800)
      end
    end

    def worker_mapping
      {
        "goal" => [RodTheBot::GoalWorker, 90],
        "penalty" => [RodTheBot::PenaltyWorker, 30],
        "shot-on-goal" => [RodTheBot::GoalieChangeWorker, 5],
        "period-start" => [RodTheBot::PeriodStartWorker, 1],
        "period-end" => [RodTheBot::EndOfPeriodWorker, 180]
      }
    end
  end
end
