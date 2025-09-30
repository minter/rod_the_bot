require "test_helper"

class RodTheBot::TodaysScheduleWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::TodaysScheduleWorker.new
    ENV["TIME_ZONE"] = "America/New_York"
    Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])

    # Stub NhlApi.postseason? to prevent HTTP requests during tests
    NhlApi.stubs(:postseason?).returns(false)
  end

  test "perform with games scheduled" do
    VCR.use_cassette("nhl_schedule_20241008") do
      Timecop.freeze(Time.zone.local(2024, 10, 8)) do
        @worker.perform

        assert_equal 1, RodTheBot::Post.jobs.size
        post = RodTheBot::Post.jobs.first["args"].first

        assert_match(/🗓️  Today's NHL schedule \(times EDT\)/, post)
        assert_match(/BOS @ FLA - 7 PM/, post)
        assert_match(/CHI @ UTA - 10 PM/, post)
        assert_no_match(/No games scheduled/, post)
      end
    end
  end

  test "perform with no games scheduled" do
    VCR.use_cassette("nhl_schedule_20241006") do
      Timecop.freeze(Time.zone.local(2024, 10, 6)) do
        @worker.perform

        assert_equal 1, RodTheBot::Post.jobs.size
        post = RodTheBot::Post.jobs.first["args"].first

        assert_match(/🗓️  Today's NHL schedule \(times EDT\)/, post)
        assert_match(/No games scheduled/, post)
      end
    end
  end

  test "format_schedule with games" do
    VCR.use_cassette("nhl_schedule_20241008") do
      date = "2024-10-08"
      schedule = NhlApi.fetch_league_schedule(date: date)

      formatted_schedule = @worker.send(:format_schedule, schedule, date)

      # format_schedule returns an array of game strings
      assert_kind_of Array, formatted_schedule
      assert formatted_schedule.any?

      # Join to string for content matching
      schedule_text = formatted_schedule.join("\n")
      assert_match(/BOS @ FLA - 7 PM/, schedule_text)
      assert_match(/CHI @ UTA - 10 PM/, schedule_text)
      assert_no_match(/No games scheduled/, schedule_text)
    end
  end

  test "format_schedule with no games" do
    VCR.use_cassette("nhl_schedule_20241006") do
      date = "2024-10-06"
      schedule = NhlApi.fetch_league_schedule(date: date)

      formatted_schedule = @worker.send(:format_schedule, schedule, date)

      # format_schedule returns an empty array when no games, not a string
      assert_equal [], formatted_schedule
      assert formatted_schedule.empty?
    end
  end

  test "format_game_time" do
    VCR.use_cassette("nhl_schedule_20241006") do
      date = "2024-10-06"
      schedule = NhlApi.fetch_league_schedule(date: date)
      game = schedule["gameWeek"][2]["games"].first
      formatted_time = @worker.send(:format_game_time, game)

      assert_equal "4:30 PM", formatted_time
    end
  end

  test "format_non_ok_game_time" do
    VCR.use_cassette("nhl_schedule_20241006") do
      date = "2024-10-06"
      schedule = NhlApi.fetch_league_schedule(date: date)
      game = schedule["gameWeek"][1]["games"].first
      formatted_time = @worker.send(:format_game_time, game)

      assert_equal "CNCL", formatted_time
    end
  end

  test "series_status with team leading" do
    game = {
      "seriesStatus" => {
        "topSeedTeamAbbrev" => "FLA",
        "topSeedWins" => 2,
        "bottomSeedTeamAbbrev" => "TBL",
        "bottomSeedWins" => 1
      }
    }

    status = @worker.send(:series_status, game)
    assert_equal " (FLA leads 2-1)", status
  end

  test "series_status with series tied" do
    game = {
      "seriesStatus" => {
        "topSeedTeamAbbrev" => "DAL",
        "topSeedWins" => 2,
        "bottomSeedTeamAbbrev" => "COL",
        "bottomSeedWins" => 2
      }
    }

    status = @worker.send(:series_status, game)
    assert_equal " (Series tied at 2)", status
  end

  test "series_status with bottom seed leading" do
    game = {
      "seriesStatus" => {
        "topSeedTeamAbbrev" => "TBL",
        "topSeedWins" => 1,
        "bottomSeedTeamAbbrev" => "FLA",
        "bottomSeedWins" => 2
      }
    }

    status = @worker.send(:series_status, game)
    assert_equal " (FLA leads 2-1)", status
  end

  def teardown
    Sidekiq::Worker.clear_all
  end
end
