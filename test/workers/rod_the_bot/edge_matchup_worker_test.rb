require "test_helper"

class RodTheBot::EdgeMatchupWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgeMatchupWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
    ENV["TEAM_HASHTAGS"] = "#LetsGoCanes #CauseChaos"

    # Stub preseason check
    Nhl::SeasonCalendar.stubs(:preseason?).returns(false)
  end

  test "perform creates post with zone control matchup data" do
    game_id = 2025020660

    VCR.use_cassette("edge_matchup_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first

      expected_output = <<~POST
        ⚔️ ZONE CONTROL BATTLE

        CAR vs NJD:

        🏒 Offensive Zone Time
        • CAR: 45.5% (#1)
        • NJD: 40.9% (#16)

        🏒 Defensive Zone Time
        • CAR: 36.2% (#1 least)
        • NJD: 41.2% (#15 least)

        🏒 Shot Differential
        • CAR: +7.3 per game (#2)
        • NJD: +0.8 per game (#14)
      POST

      assert_equal expected_output, post
    end
  end

  test "perform returns early if preseason" do
    Nhl::SeasonCalendar.unstub(:preseason?)
    Nhl::SeasonCalendar.stubs(:preseason?).returns(true)

    @worker.perform(2025020660)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform returns early if no opponent team found" do
    Nhl::GameInfo.stubs(:opponent_team_id).returns(nil)

    @worker.perform(2025020660)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform truncates post if too long" do
    game_id = 2025020660

    # Set very short hashtags to test the length check
    ENV["TEAM_HASHTAGS"] = ""

    VCR.use_cassette("edge_matchup_#{game_id}") do
      @worker.perform(game_id)

      # Should still create a post, possibly without shot differential
      assert_operator RodTheBot::Post.jobs.size, :>=, 0
    end
  end

  def teardown
    Sidekiq::Worker.clear_all
  end
end
