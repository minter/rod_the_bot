require "test_helper"

class RodTheBot::GameStreamTest < ActiveSupport::TestCase
  def setup
    @game_stream = RodTheBot::GameStream.new
    @game_id = "2023020369" # replace with a valid game_id
    ENV["NHL_TEAM_ID"] = "12" # Assuming this is needed for consistency with other tests

    # Mock preseason check to avoid VCR issues and skip milestone checking
    NhlApi.stubs(:preseason?).returns(true)  # Skip milestone achievements to avoid extra API calls
  end

  def teardown
    Sidekiq::Worker.clear_all
  end

  test "perform processes plays correctly" do
    VCR.use_cassette("game_stream_#{@game_id}_in_progress", allow_playback_repeats: true) do
      # Allow both goal-specific keys (completed/scheduled) and regular event keys
      # Goals use: "#{game_id}:goal:completed:#{eventId}" and "#{game_id}:goal:scheduled:#{eventId}"
      # Other plays use: "#{game_id}:#{eventId}"
      REDIS.expects(:get).with(regexp_matches(/#{@game_id}/)).returns(nil).at_least_once
      # Goals set scheduled key with 300s expiration, other plays set with 172800s expiration
      REDIS.expects(:set).with(regexp_matches(/#{@game_id}/), "true", ex: anything).returns("OK").at_least_once

      @game_stream.perform(@game_id)

      assert_equal @game_id, @game_stream.game_id
      assert_equal 1, RodTheBot::GameStream.jobs.size
      assert_operator RodTheBot::GoalWorker.jobs.size, :>, 0
      assert_operator RodTheBot::PeriodStartWorker.jobs.size, :>, 0
      assert_operator RodTheBot::EndOfPeriodWorker.jobs.size, :>, 0
      assert_operator RodTheBot::PenaltyWorker.jobs.size, :>, 0
    end
  end

  test "process_play enqueues correct worker" do
    # Mock preseason to prevent milestone checking which requires more complex data
    NhlApi.stubs(:preseason?).returns(true)  # Skip milestone achievements in preseason

    play = {"typeDescKey" => "goal", "eventId" => "73"}

    # For goals, the code checks completed key twice (once for logging, once for condition)
    # and scheduled key twice (once for logging, once for condition)
    REDIS.expects(:get).with("#{@game_id}:goal:completed:73").returns(nil).twice
    REDIS.expects(:get).with("#{@game_id}:goal:scheduled:73").returns(nil).twice
    REDIS.expects(:set).with("#{@game_id}:goal:scheduled:73", "true", ex: 300).returns("OK")

    @game_stream.instance_variable_set(:@game_id, @game_id)
    @game_stream.send(:process_play, play)

    assert_equal 1, RodTheBot::GoalWorker.jobs.size
    job = RodTheBot::GoalWorker.jobs.first
    assert_equal @game_id, job["args"][0]
    assert_equal play, job["args"][1]
  end

  test "worker_mapping returns correct mapping" do
    expected_mapping = {
      "goal" => [RodTheBot::GoalWorker, 90],
      "penalty" => [RodTheBot::PenaltyWorker, 30],
      "shot-on-goal" => [RodTheBot::GoalieChangeWorker, 5],
      "period-start" => [RodTheBot::PeriodStartWorker, 1],
      "period-end" => [RodTheBot::EndOfPeriodWorker, 180]
    }

    assert_equal expected_mapping, @game_stream.send(:worker_mapping)
  end
end
