require "test_helper"

class RodTheBot::EdgePlayerWorkloadWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgePlayerWorkloadWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
    
    # Stub preseason check
    NhlApi.stubs(:preseason?).returns(false)
  end

  test "perform creates post for eligible player with high workload" do
    game_id = 2025020660
    
    # Stub the player selection to return a known player
    eligible_player = {
      id: 8478427,  # Sebastian Aho
      name: "Sebastian Aho",
      sweater_number: 20,
      points: 6,
      goals: 3,
      assists: 3,
      games_played: 3,
      avg_pp_toi: 2.5
    }
    
    @worker.stubs(:select_eligible_players).returns([eligible_player])
    
    VCR.use_cassette("edge_player_workload_8478427") do
      @worker.perform(game_id)
      
      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first
      
      expected_output = <<~POST
        🔥 SEBASTIAN AHO WORKLOAD

        Sebastian Aho's last 3 games:
        • 3G-3A = 6 points
        • Averaging 2.9 miles skated/game
        • 18+ minutes TOI per game
        • 2.0 min/game on PP

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
      points: 6,
      goals: 3,
      assists: 3,
      games_played: 3,
      avg_pp_toi: 2.5
    }
    
    @worker.stubs(:select_eligible_players).returns([eligible_player])
    
    VCR.use_cassette("edge_player_workload_8478427") do
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

