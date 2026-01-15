require "test_helper"

class RodTheBot::EdgeReplayWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgeReplayWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"

    # Create output directory for tests
    @output_dir = Rails.root.join("tmp", "edge_replays")
    FileUtils.mkdir_p(@output_dir)
    @created_files = []
  end

  test "perform returns early if replay already exists" do
    game_id = 2025020660
    event_id = 544

    # Create a dummy replay file
    output_path = @output_dir.join("#{game_id}_#{event_id}_replay.mp4")
    FileUtils.touch(output_path)
    @created_files << output_path

    result = @worker.perform(game_id, event_id)

    assert_equal output_path.to_s, result
    # Should not create a post job since no redis_key provided
    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform retries if EDGE JSON not available" do
    game_id = 2025020660
    event_id = 999999 # Non-existent event
    redis_key = "test_key"

    # Stub download_edge_json to return nil (not available)
    @worker.stubs(:download_edge_json).returns(nil)

    result = @worker.perform(game_id, event_id, redis_key, 0)

    assert_nil result
    # Should schedule a retry
    assert_equal 1, RodTheBot::EdgeReplayWorker.jobs.size
  end

  test "perform does not retry if max retries reached" do
    game_id = 2025020660
    event_id = 999999
    redis_key = "test_key"

    # Stub download_edge_json to return nil
    @worker.stubs(:download_edge_json).returns(nil)

    result = @worker.perform(game_id, event_id, redis_key, 5) # Max retries

    assert_nil result
    # Should not schedule another retry
    assert_equal 0, RodTheBot::EdgeReplayWorker.jobs.size
  end

  test "perform handles missing game data gracefully" do
    game_id = 2025020660
    event_id = 544
    redis_key = "test_key"

    # Stub methods to simulate missing game data
    @worker.stubs(:download_edge_json).returns("/tmp/fake.json")
    @worker.stubs(:fetch_game_data).returns(nil)

    result = @worker.perform(game_id, event_id, redis_key, 0)

    assert_nil result
    # Should schedule a retry
    assert_equal 1, RodTheBot::EdgeReplayWorker.jobs.size
  end

  test "generate_replay creates video file with valid data" do
    skip "Requires FFmpeg and complex video processing setup"
    # This test would require actual EDGE JSON data and FFmpeg installed
    # Skipping for now as it's an integration test
  end

  def teardown
    Sidekiq::Worker.clear_all
    @created_files.each do |file|
      File.delete(file) if File.exist?(file)
    end
  end
end
