require "test_helper"

class RodTheBot::ThreeMinuteRecapWorkerTest < ActiveSupport::TestCase
  test "forwards already-enqueued legacy jobs to the game video worker" do
    assert_difference -> { RodTheBot::GameVideoWorker.jobs.size }, 1 do
      RodTheBot::ThreeMinuteRecapWorker.new.perform(2024020020, 2)
    end

    assert_equal [2024020020, "threeMinRecap", 2], RodTheBot::GameVideoWorker.jobs.last["args"]
  end
end
