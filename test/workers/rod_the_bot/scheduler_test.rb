require "test_helper"

class RodTheBot::SchedulerTest < ActiveSupport::TestCase
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
        NhlApi.stubs(:offseason?).returns(false)
        NhlApi.stubs(:preseason?).returns(false)  # Mock preseason check
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
        NhlApi.stubs(:offseason?).returns(false)
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
        NhlApi.stubs(:offseason?).returns(false)
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

  def test_playoff_series_state_tied
    series = {"topSeedWins" => 0, "bottomSeedWins" => 0, "topSeedTeamAbbrev" => "CAR", "bottomSeedTeamAbbrev" => "OTT"}
    assert_equal "Series tied 0-0", @worker.send(:playoff_series_state, series)
  end

  def test_playoff_series_state_top_seed_leads
    series = {"topSeedWins" => 2, "bottomSeedWins" => 1, "topSeedTeamAbbrev" => "CAR", "bottomSeedTeamAbbrev" => "OTT"}
    assert_equal "CAR leads 2-1", @worker.send(:playoff_series_state, series)
  end

  def test_playoff_series_state_bottom_seed_leads
    series = {"topSeedWins" => 1, "bottomSeedWins" => 2, "topSeedTeamAbbrev" => "CAR", "bottomSeedTeamAbbrev" => "OTT"}
    assert_equal "OTT leads 2-1", @worker.send(:playoff_series_state, series)
  end

  def test_playoff_status_line_game_one
    series = {
      "round" => 1,
      "gameNumberOfSeries" => 1,
      "topSeedWins" => 0,
      "bottomSeedWins" => 0,
      "topSeedTeamAbbrev" => "CAR",
      "bottomSeedTeamAbbrev" => "OTT"
    }
    assert_equal "Round 1, Game 1 — Series tied 0-0", @worker.send(:playoff_status_line, series)
  end

  def test_playoff_status_line_mid_series
    series = {
      "round" => 2,
      "gameNumberOfSeries" => 4,
      "topSeedWins" => 2,
      "bottomSeedWins" => 1,
      "topSeedTeamAbbrev" => "CAR",
      "bottomSeedTeamAbbrev" => "OTT"
    }
    assert_equal "Round 2, Game 4 — CAR leads 2-1", @worker.send(:playoff_status_line, series)
  end

  def teardown
    Sidekiq::Worker.clear_all
    NhlApi.unstub(:current_season)
  end
end
