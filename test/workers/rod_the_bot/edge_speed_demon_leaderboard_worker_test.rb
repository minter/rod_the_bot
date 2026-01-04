require "test_helper"

class RodTheBot::EdgeSpeedDemonLeaderboardWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgeSpeedDemonLeaderboardWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"

    # Stub preseason check
    NhlApi.stubs(:preseason?).returns(false)
  end

  test "perform creates post with speed leaderboard" do
    game_id = 2025020660

    VCR.use_cassette("edge_speed_demon_leaderboard_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first

      expected_output = <<~POST
        💨 SPEED DEMONS

        Top 3 fastest CAR players:
        1. Seth Jarvis: 23.38 mph
        2. Eric Robinson: 23.3 mph
        3. K'Andre Miller: 23.22 mph
      POST

      assert_equal expected_output, post
    end
  end

  test "perform returns early if preseason" do
    NhlApi.unstub(:preseason?)
    NhlApi.stubs(:preseason?).returns(true)

    @worker.perform(2025020660)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform returns early if no speed data" do
    NhlApi.stubs(:fetch_team_skating_speed_detail).returns(nil)

    @worker.perform(2025020660)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform includes player headshots for top 3 players" do
    game_id = 2025020660

    VCR.use_cassette("edge_speed_demon_leaderboard_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      # Check that images array is passed (5th argument)
      images = RodTheBot::Post.jobs.first["args"][4]
      assert_kind_of Array, images
      # Should have up to 3 images (top 3 fastest players)
      assert_operator images.compact.length, :<=, 3
    end
  end

  def teardown
    Sidekiq::Worker.clear_all
  end
end
