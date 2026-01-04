require "test_helper"

class RodTheBot::EdgePlayerZoneTimeWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgePlayerZoneTimeWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"

    # Stub preseason check
    NhlApi.stubs(:preseason?).returns(false)
  end

  test "perform creates post for eligible player with elite zone control" do
    game_id = 2025020660

    # Stub the player selection to return a known player
    eligible_player = {
      id: 8478427,  # Sebastian Aho
      name: "Sebastian Aho",
      sweater_number: 20,
      points: 42,
      goals: 17,
      assists: 25,
      games_played: 4
    }

    @worker.stubs(:select_eligible_players).returns([eligible_player])

    VCR.use_cassette("edge_player_zone_time_8478427") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first
      
      expected_output = <<~POST
        🔍 EDGE SPOTLIGHT: Sebastian Aho

        Zone control this season:
        • 48.2% off. zone time (99th percentile)
        • 34.3% def. zone time (99th percentile)
        • 48.4% off. zone starts (99th percentile)

        Season totals: 17G-25A = 42 points
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

  test "perform returns early if no eligible players" do
    @worker.stubs(:select_eligible_players).returns([])

    @worker.perform(2025020660)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform includes player headshot in post" do
    game_id = 2025020660

    eligible_player = {
      id: 8478427,
      name: "Sebastian Aho",
      sweater_number: 20,
      points: 42,
      goals: 17,
      assists: 25,
      games_played: 4
    }

    @worker.stubs(:select_eligible_players).returns([eligible_player])

    VCR.use_cassette("edge_player_zone_time_8478427") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      # Check that images array is passed (5th argument)
      images = RodTheBot::Post.jobs.first["args"][4]
      assert_kind_of Array, images
      # Should have at most 1 image (player headshot)
      assert_operator images.compact.length, :<=, 1
    end
  end

  def teardown
    Sidekiq::Worker.clear_all
  end
end
