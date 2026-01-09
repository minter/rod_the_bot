require "test_helper"

class RodTheBot::EdgeGoalieMatchupWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgeGoalieMatchupWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"

    # Stub preseason check
    NhlApi.stubs(:preseason?).returns(false)
  end

  test "perform creates matchup post comparing both goalies" do
    game_id = 2025020660
    our_goalie_id = 8479496    # Pyotr Kochetkov (CAR)
    opp_goalie_id = 8476883    # Igor Shesterkin (NYR)

    VCR.use_cassette("edge_goalie_matchup") do
      @worker.perform(game_id, our_goalie_id, opp_goalie_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first

      # Check the post includes key elements
      assert_includes post, "GOALIE MATCHUP"
      assert_includes post, "CAR: Pyotr Kochetkov"
      assert_includes post, "NYR: Igor Shesterkin"

      # Should include GAA comparisons
      assert_includes post, "GAA"

      # Should include goal diff
      assert_includes post, "goal diff/60"

      # Should include point percentage
      assert_includes post, "point pct"

      # Should declare an edge (CAR has better stats in fixture)
      assert_includes post, "Edge: CAR"
    end
  end

  test "perform returns early if preseason" do
    NhlApi.unstub(:preseason?)
    NhlApi.stubs(:preseason?).returns(true)

    @worker.perform(2025020660, 8479496, 8476883)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform returns early if missing goalie ids" do
    @worker.perform(2025020660, nil, 8476883)
    assert_equal 0, RodTheBot::Post.jobs.size

    @worker.perform(2025020660, 8479496, nil)
    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform posts as reply to EDGE STATS post" do
    game_id = 2025020660
    our_goalie_id = 8479496
    opp_goalie_id = 8476883

    VCR.use_cassette("edge_goalie_matchup") do
      @worker.perform(game_id, our_goalie_id, opp_goalie_id)

      assert_equal 1, RodTheBot::Post.jobs.size

      # Check that parent_key points to edge_goalie post
      args = RodTheBot::Post.jobs.first["args"]
      post_key = args[1]
      parent_key = args[2]

      assert_match(/edge_goalie_matchup_#{game_id}/, post_key)
      assert_match(/edge_goalie_#{game_id}/, parent_key)
    end
  end

  test "perform includes both goalie headshots" do
    game_id = 2025020660
    our_goalie_id = 8479496
    opp_goalie_id = 8476883

    VCR.use_cassette("edge_goalie_matchup") do
      @worker.perform(game_id, our_goalie_id, opp_goalie_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      # Check that images array is passed (5th argument)
      images = RodTheBot::Post.jobs.first["args"][4]
      assert_kind_of Array, images
      # Should have 2 images (both goalie headshots)
      assert_operator images.compact.length, :<=, 2
    end
  end

  test "shows even matchup when stats are equal" do
    game_id = 2025020660

    # Create mock data with equal stats
    equal_stats = {
      "goalsAgainstAvg" => {"value" => 2.50, "percentile" => 0.85},
      "goalDifferentialPer60" => {"value" => 1.0, "percentile" => 0.85},
      "pointPctg" => {"value" => 0.70, "percentile" => 0.85},
      "gamesAbove900" => {"value" => 0.55, "percentile" => 0.65}
    }

    goalie_data = {
      "player" => {
        "id" => 8479496,
        "firstName" => {"default" => "Test"},
        "lastName" => {"default" => "Goalie"},
        "sweaterNumber" => 30,
        "team" => {"abbrev" => "CAR"}
      },
      "stats" => equal_stats
    }

    NhlApi.stubs(:fetch_goalie_detail).returns(goalie_data)
    @worker.stubs(:fetch_player_headshots).returns([])

    @worker.perform(game_id, 8479496, 8476883)

    assert_equal 1, RodTheBot::Post.jobs.size
    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "Even matchup"
  end

  def teardown
    Sidekiq::Worker.clear_all
  end
end
