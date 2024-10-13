require "test_helper"

class RodTheBot::ThreeMinuteRecapWorkerTest < ActiveSupport::TestCase
  def setup
    @worker = RodTheBot::ThreeMinuteRecapWorker.new
    @game_id = 2024020020
    ENV["TIME_ZONE"] = "America/New_York"
    Sidekiq::Worker.clear_all
  end

  def test_perform_with_available_recap
    VCR.use_cassette("nhl_game_#{@game_id}_with_recap") do
      assert_difference -> { RodTheBot::Post.jobs.size }, 1 do
        assert_no_difference -> { RodTheBot::ThreeMinuteRecapWorker.jobs.size } do
          @worker.perform(@game_id)
        end
      end
    end

    last_job = RodTheBot::Post.jobs.last
    assert_match(/The three-minute recap for .+ at .+ on .+ is now available!/, last_job["args"].first)
    assert_match %r{https://nhl.com/.*}, last_job["args"].last
  end

  def test_perform_without_available_recap
    mock_boxscore = {"gameDate" => "2024-10-11"}
    mock_game_data = {
      "id" => @game_id,
      "gameScheduleState" => "OK",
      "threeMinRecap" => nil,
      "awayTeam" => {"placeName" => {"default" => "Tampa Bay"}},
      "homeTeam" => {"placeName" => {"default" => "Carolina"}},
      "startTimeUTC" => "2024-10-11T23:00:00Z"
    }
    mock_schedule = {"gameWeek" => [{"games" => [mock_game_data]}]}

    NhlApi.stubs(:fetch_boxscore_feed).returns(mock_boxscore)
    NhlApi.stubs(:fetch_league_schedule).returns(mock_schedule)

    assert_no_difference -> { RodTheBot::Post.jobs.size } do
      assert_difference -> { RodTheBot::ThreeMinuteRecapWorker.jobs.size }, 1 do
        @worker.perform(@game_id)
      end
    end

    last_job = RodTheBot::ThreeMinuteRecapWorker.jobs.last
    assert_equal [@game_id], last_job["args"]
    assert_in_delta 600, last_job["at"] - Time.now.to_f, 1
  end

  def test_perform_with_invalid_game_schedule_state
    mock_boxscore = {"gameDate" => "2024-10-11"}
    mock_game_data = {
      "id" => @game_id,
      "gameScheduleState" => "NOT_OK",
      "threeMinRecap" => nil,
      "awayTeam" => {"placeName" => {"default" => "Tampa Bay"}},
      "homeTeam" => {"placeName" => {"default" => "Carolina"}},
      "startTimeUTC" => "2024-10-11T23:00:00Z"
    }
    mock_schedule = {"gameWeek" => [{"games" => [mock_game_data]}]}

    NhlApi.stubs(:fetch_boxscore_feed).returns(mock_boxscore)
    NhlApi.stubs(:fetch_league_schedule).returns(mock_schedule)

    assert_no_difference -> { RodTheBot::Post.jobs.size } do
      assert_no_difference -> { RodTheBot::ThreeMinuteRecapWorker.jobs.size } do
        @worker.perform(@game_id)
      end
    end
  end

  def test_perform_with_nil_game
    mock_boxscore = {"gameDate" => "2024-10-11"}
    mock_schedule = {"gameWeek" => [{"games" => []}]}

    NhlApi.stubs(:fetch_boxscore_feed).returns(mock_boxscore)
    NhlApi.stubs(:fetch_league_schedule).returns(mock_schedule)

    assert_no_difference -> { RodTheBot::Post.jobs.size } do
      assert_no_difference -> { RodTheBot::ThreeMinuteRecapWorker.jobs.size } do
        @worker.perform(@game_id)
      end
    end
  end

  def test_format_recap
    mock_game_data = {
      "awayTeam" => {"placeName" => {"default" => "Tampa Bay"}},
      "homeTeam" => {"placeName" => {"default" => "Carolina"}},
      "startTimeUTC" => "2024-10-11T23:00:00Z"
    }

    expected_output = "The three-minute recap for Tampa Bay at Carolina on Friday, October 11 2024 is now available!\n"

    assert_equal expected_output, @worker.send(:format_recap, mock_game_data)
  end
end
