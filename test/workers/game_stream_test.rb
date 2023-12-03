require "minitest/autorun"
require "vcr"

module RodTheBot
  class GameStreamTest < Minitest::Test
    def setup
      Sidekiq::Worker.clear_all
      Sidekiq.redis(&:flushdb)
      @game_stream = GameStream.new
      @game_id = "2023020369" # replace with a valid game_id
    end

    def test_perform
      VCR.use_cassette("game_stream_#{@game_id}_in_progress") do
        @game_stream.perform(@game_id)
      end

      assert_equal @game_id, @game_stream.game_id
      assert_equal 1, RodTheBot::GameStream.jobs.size
      assert_equal 3, RodTheBot::GoalWorker.jobs.size
      assert_equal 1, RodTheBot::PeriodStartWorker.jobs.size
      assert_equal 1, RodTheBot::EndOfPeriodWorker.jobs.size
      assert_equal 2, RodTheBot::PenaltyWorker.jobs.size
    end

    def test_process_play
      play = {"typeDescKey" => "goal", "eventId" => "73"}

      VCR.use_cassette("game_stream_#{@game_id}_in_progress") do
        @game_stream.send(:process_play, play)
      end

      # assert_equal "true", REDIS.get("#{@game_id}:#{play["eventId"]}")
      assert_equal 1, RodTheBot::GoalWorker.jobs.size
    end

    def test_worker_mapping
      expected_mapping = {
        "goal" => [RodTheBot::GoalWorker, 60],
        "penalty" => [RodTheBot::PenaltyWorker, 60],
        "period-start" => [RodTheBot::PeriodStartWorker, 1],
        "period-end" => [RodTheBot::EndOfPeriodWorker, 90]
      }

      assert_equal expected_mapping, @game_stream.send(:worker_mapping)
    end
  end
end
