module RodTheBot
  class GameStream
    include Sidekiq::Worker
    include RodTheBot::PlayerFormatter

    attr_reader :feed, :game_id

    def perform(game_id)
      @game_id = game_id
      @feed = NhlApi.fetch_pbp_feed(game_id)
      plays = @feed&.dig("plays") || []

      # Check if game is final using gameState (works even when plays are empty)
      game_final = @feed&.dig("gameState") == "OFF" || plays.find { |play| play["typeDescKey"] == "game-end" }.present?

      # Process plays if they exist
      plays.each do |play|
        process_play(play)
      end

      if game_final
        RodTheBot::FinalScoreWorker.perform_in(60, game_id)
        RodTheBot::ThreeStarsWorker.perform_in(90, game_id)
        RodTheBot::ThreeMinuteRecapWorker.perform_in(600, game_id)
      else
        RodTheBot::GameStream.perform_in(30, game_id)
      end
    rescue NhlApi::APIError => e
      Rails.logger.error "GameStream: API error for game #{game_id}: #{e.message}. Retrying in 30 seconds."
      RodTheBot::GameStream.perform_in(30, game_id)
    rescue => e
      Rails.logger.error "GameStream: Unexpected error for game #{game_id}: #{e.class} - #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      RodTheBot::GameStream.perform_in(30, game_id)
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

      if play["typeDescKey"] == "goal"
        # Use atomic SET NX to prevent duplicate goal scheduling across concurrent workers
        scheduled_key = "#{game_id}:goal:scheduled:#{play["eventId"]}"
        if REDIS.get(redis_key).nil? && REDIS.set(scheduled_key, "true", nx: true, ex: 300)
          worker_class.perform_in(delay, game_id, play)
        end
      elsif REDIS.set(redis_key, "true", nx: true, ex: 172800)
        # Use atomic SET NX to prevent duplicate event processing
        worker_class.perform_in(delay, game_id, play)
      end

      # Schedule milestone check with delay to allow NHL API stats to update (only during regular season and playoffs)
      schedule_milestone_check(play) unless NhlApi.preseason?
    end

    def schedule_milestone_check(play)
      # Schedule milestone check immediately since we calculate from pre-game stats
      # Use atomic SET NX to prevent duplicate milestone checks
      milestone_key = "#{game_id}:milestone:#{play["eventId"]}"

      if REDIS.set(milestone_key, "true", nx: true, ex: 172800)
        # Check immediately (30 seconds after the play) using pre-game stats + in-game calculation
        RodTheBot::MilestoneCheckerWorker.perform_in(30, game_id, play)
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
