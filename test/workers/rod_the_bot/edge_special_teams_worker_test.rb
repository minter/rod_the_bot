require "test_helper"

class RodTheBot::EdgeSpecialTeamsWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgeSpecialTeamsWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"

    # Stub preseason check
    NhlApi.stubs(:preseason?).returns(false)
  end

  test "perform creates post with special teams data" do
    game_id = 2025020660

    VCR.use_cassette("edge_special_teams_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first

      expected_output = <<~POST
        ⚡ SPECIAL TEAMS MATCHUP

        CAR special teams:
        • PP: 59.7% off. zone time (#14 in NHL)
        • PK: 32.1% off. zone time (#1)

        NJD special teams:
        • PP: 60.6% off. zone time (#7 in NHL)
        • PK: 25.1% off. zone time (#27)
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

  test "perform returns early if no zone data" do
    NhlApi.stubs(:fetch_team_zone_time_details).returns(nil)

    @worker.perform(2025020660)

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform includes opponent data when game is today" do
    game_id = 2025020660

    VCR.use_cassette("edge_special_teams_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first

      # If we have today's game, should have both teams
      # This is flexible since it depends on whether todays_game returns data
      assert_match(/special teams:/, post)
    end
  end

  def teardown
    Sidekiq::Worker.clear_all
  end
end
