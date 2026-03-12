require "test_helper"

class RodTheBot::EdgeTeamShotSpeedWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgeTeamShotSpeedWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"

    # Stub preseason check
    NhlApi.stubs(:preseason?).returns(false)
  end

  test "perform creates post with shot speed data" do
    game_id = 2025020660
    NhlApi.stubs(:roster).with("CAR").returns({8482100 => {}})
    NhlApi.stubs(:roster).with("NJD").returns({8479772 => {}})

    VCR.use_cassette("edge_team_shot_speed_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first

      expected_output = <<~POST
        🎯 SHOT SPEED PREVIEW

        CAR shot speed:
        • Average: 59.56 mph (#5 in NHL)
        • Hardest: 98.97 mph (#13)
        • Hardest shot: Alexander Nikishin

        NJD shot speed:
        • Average: 57.0 mph (#27 in NHL)
        • Hardest: 99.2 mph (#9)
        • Hardest shot: Zack MacEwen
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

  test "perform returns early if no shot speed data" do
    NhlApi.stubs(:fetch_team_shot_speed_detail).returns(nil)

    @worker.perform(2025020660)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "filters out traded players and shows next active player" do
    game_id = 2025020660
    # Simulate Nikishin being traded - CAR roster only has a different player
    NhlApi.stubs(:roster).with("CAR").returns({8479407 => {}})
    NhlApi.stubs(:roster).with("NJD").returns({8479772 => {}})

    VCR.use_cassette("edge_team_shot_speed_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first
      # Should not show Nikishin since he's no longer on the roster
      assert_not_includes post, "Alexander Nikishin"
    end
  end

  test "perform includes player headshots when available" do
    game_id = 2025020660
    NhlApi.stubs(:roster).with("CAR").returns({8482100 => {}})
    NhlApi.stubs(:roster).with("NJD").returns({8479772 => {}})

    VCR.use_cassette("edge_team_shot_speed_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      # Check that images array is passed (5th argument)
      images = RodTheBot::Post.jobs.first["args"][4]
      assert_kind_of Array, images
      # Should have up to 2 images (hardest shot from each team)
      assert_operator images.compact.length, :<=, 2
    end
  end

  test "filters out Justin Faulk (traded from STL) for STL @ CAR game" do
    game_id = 2025021033

    VCR.use_cassette("edge_team_shot_speed_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first
      # Faulk (8475753) was traded to DET mid-season and should not appear
      assert_not_includes post, "Justin Faulk"
      # The next active STL player should be shown instead
      assert_includes post, "Jimmy Snuggerud"
      assert_includes post, "STL shot speed:"
    end
  end

  def teardown
    Sidekiq::Worker.clear_all
  end
end
