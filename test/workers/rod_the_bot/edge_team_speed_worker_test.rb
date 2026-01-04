require "test_helper"

class RodTheBot::EdgeTeamSpeedWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgeTeamSpeedWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"

    # Stub preseason check
    NhlApi.stubs(:preseason?).returns(false)
  end

  test "perform creates post with team speed data" do
    game_id = 2025020660

    VCR.use_cassette("edge_team_speed_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      post = RodTheBot::Post.jobs.first["args"].first

      expected_output = <<~POST
        💨 SPEED MATCHUP

        CAR speed:
        • Top speed: 23.38 mph (#23 in NHL)
        • Fastest: Seth Jarvis
        • 55 bursts over 22 mph (#9)
        • 915 bursts 20-22 mph (#11)

        NJD speed:
        • Top speed: 23.23 mph (#25 in NHL)
        • Fastest: Connor Brown
        • 36 bursts over 22 mph (#22)
        • 776 bursts 20-22 mph (#20)
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

  test "perform includes player headshots when available" do
    game_id = 2025020660

    VCR.use_cassette("edge_team_speed_#{game_id}") do
      @worker.perform(game_id)

      assert_equal 1, RodTheBot::Post.jobs.size
      # Check that images array is passed (5th argument)
      images = RodTheBot::Post.jobs.first["args"][4]
      assert_kind_of Array, images
      # Should have up to 2 images (fastest player from each team)
      assert_operator images.compact.length, :<=, 2
    end
  end

  def teardown
    Sidekiq::Worker.clear_all
  end
end
