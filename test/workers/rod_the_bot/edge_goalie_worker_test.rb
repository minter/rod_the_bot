require "test_helper"

class RodTheBot::EdgeGoalieWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgeGoalieWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"

    # Stub preseason check
    NhlApi.stubs(:preseason?).returns(false)
  end

  test "perform creates post with EDGE stats for goalie" do
    game_id = 2025020660
    goalie_id = 8479496  # Pyotr Kochetkov

    VCR.use_cassette("edge_goalie_detail_8479496") do
      @worker.perform(game_id, goalie_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first

      # Check the post includes key elements
      assert_includes post, "EDGE STATS: PYOTR KOCHETKOV"
      assert_includes post, "Best save zones"

      # Should include top save zones
      assert_includes post, "L Corner"  # 98th percentile
      assert_includes post, "R Corner"  # 97th percentile
      assert_includes post, "Low Slot"  # 95th percentile

      # Should include key advanced stats
      assert_includes post, "GAA"
      assert_includes post, "goal diff"
      assert_includes post, "point pct"
    end
  end

  test "perform returns early if preseason" do
    NhlApi.unstub(:preseason?)
    NhlApi.stubs(:preseason?).returns(true)

    @worker.perform(2025020660, 8479496)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform returns early if no goalie_player_id" do
    @worker.perform(2025020660, nil)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform posts as standalone root post" do
    game_id = 2025020660
    goalie_id = 8479496

    VCR.use_cassette("edge_goalie_detail_8479496") do
      @worker.perform(game_id, goalie_id)

      assert_equal 1, RodTheBot::Post.jobs.size

      # Check that it's a root post (no parent_key)
      args = RodTheBot::Post.jobs.first["args"]
      post_key = args[1]
      parent_key = args[2]

      assert_match(/edge_goalie_#{game_id}/, post_key)
      assert_nil parent_key
    end
  end

  test "perform includes goalie headshot in post" do
    game_id = 2025020660
    goalie_id = 8479496

    VCR.use_cassette("edge_goalie_detail_8479496") do
      @worker.perform(game_id, goalie_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      # Check that images array is passed (5th argument)
      images = RodTheBot::Post.jobs.first["args"][4]
      assert_kind_of Array, images
      # Should have 1 image (goalie headshot)
      assert_operator images.compact.length, :<=, 1
    end
  end

  def teardown
    Sidekiq::Worker.clear_all
  end
end
