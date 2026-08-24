module RodTheBot
  class ThreeMinuteRecapWorker
    include Sidekiq::Worker

    def perform(game_id, retry_count = 0)
      RodTheBot::GameVideoWorker.perform_async(game_id, "threeMinRecap", retry_count)
    end
  end
end
