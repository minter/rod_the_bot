module RodTheBot
  class GameStream
    include Sidekiq::Worker

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

      if REDIS.get("#{game_id}:#{play["eventId"]}").nil?
        worker_class.perform_in(delay, game_id, play)
        REDIS.set("#{game_id}:#{play["eventId"]}", "true", ex: 172800)
      end
    end

    def worker_mapping
      {
        "goal" => [RodTheBot::GoalWorker, 90],
        "penalty" => [RodTheBot::PenaltyWorker, 30],
        "period-start" => [RodTheBot::PeriodStartWorker, 1],
        "period-end" => [RodTheBot::EndOfPeriodWorker, 180]
      }
    end
  end
end
