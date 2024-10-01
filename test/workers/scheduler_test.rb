require "test_helper"
require "timecop"

class SchedulerTest < Minitest::Test
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::Scheduler.new
    Time.zone = ENV["TIME_ZONE"]
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
    ENV["NHL_TEAM_ID"] = "12"

    # Stub the current_season method
    NhlApi.stubs(:current_season).returns("20232024")
  end

  def test_perform_non_gameday
    VCR.use_cassette("nhl_schedule_20231201") do
      Timecop.freeze(Date.new(2023, 12, 1)) do
        NhlApi.expects(:postseason?).returns(false).at_least_once
        @worker.perform

        assert_equal 0, RodTheBot::Post.jobs.size
        assert_equal 1, RodTheBot::YesterdaysScoresWorker.jobs.size
        assert_equal 1, RodTheBot::DivisionStandingsWorker.jobs.size
      end
    end
  end

  def test_perform_gameday
    VCR.use_cassette("nhl_schedule_20231202") do
      Timecop.freeze(Date.new(2023, 12, 2)) do
        NhlApi.expects(:postseason?).returns(false).at_least_once
        NhlApi.expects(:preseason?).returns(false).at_least_once
        @worker.perform

        expected_output = <<~POST
          🗣️ It's a Carolina Hurricanes Gameday!
          
          Buffalo Sabres
          (10-11-2, 22 points)
          6th in the Atlantic
          
          at 
          
          Carolina Hurricanes
          (13-8-1, 27 points)
          2nd in the Metropolitan
          
          ⏰ 7:00 PM EST
          📍 PNC Arena
          📺 BSSO
        POST

        assert_equal 1, RodTheBot::Post.jobs.size
        assert_equal 1, RodTheBot::YesterdaysScoresWorker.jobs.size
        assert_equal 1, RodTheBot::DivisionStandingsWorker.jobs.size
        assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
      end
    end
  end

  def test_perform_preseason_gameday
    VCR.use_cassette("nhl_schedule_20240927") do
      Timecop.freeze(Date.new(2024, 9, 27)) do
        NhlApi.expects(:postseason?).returns(false).at_least_once
        NhlApi.expects(:preseason?).returns(true).at_least_once
        @worker.perform

        expected_output = <<~POST
          🗣️ It's a Carolina Hurricanes Preseason Gameday!
          
          Florida Panthers
          
          at 
          
          Carolina Hurricanes
          
          ⏰ 6:00 PM EDT
          📍 Lenovo Center
          📺 NHLN
        POST

        assert_equal 1, RodTheBot::Post.jobs.size
        assert_equal 1, RodTheBot::YesterdaysScoresWorker.jobs.size
        assert_equal 1, RodTheBot::DivisionStandingsWorker.jobs.size
        assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
      end
    end
  end

  def teardown
    Sidekiq::Worker.clear_all
    NhlApi.unstub(:current_season)
  end
end
