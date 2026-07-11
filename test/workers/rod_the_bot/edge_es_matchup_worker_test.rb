require "test_helper"

class RodTheBot::EdgeEsMatchupWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgeEsMatchupWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"

    # Stub preseason check
    Nhl::SeasonCalendar.stubs(:preseason?).returns(false)
  end

  test "perform creates post with 5v5 zone control matchup data" do
    game_id = 2025020660

    VCR.use_cassette("edge_es_matchup_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first

      expected_output = <<~POST
        ⚔️ 5V5 ZONE CONTROL

        CAR vs NJD:

        🏒 Offensive Zone Time
        • CAR: 45.2% (#1)
        • NJD: 40.6% (#14)

        🏒 Defensive Zone Time
        • CAR: 35.7% (#1 least)
        • NJD: 40.7% (#14 least)
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

  def teardown
    Sidekiq::Worker.clear_all
  end
end
