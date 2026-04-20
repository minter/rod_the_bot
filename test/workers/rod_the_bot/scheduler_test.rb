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

  def test_perform_postseason_gameday
    game = {
      "id" => 2025030134,
      "gameScheduleState" => "OK",
      "startTimeUTC" => "2026-04-24T23:00:00Z",
      "venue" => {"default" => "Lenovo Center"},
      "homeTeam" => {"id" => 12, "abbrev" => "CAR", "logo" => "home.svg"},
      "awayTeam" => {"id" => 9, "abbrev" => "OTT", "logo" => "away.svg"},
      "tvBroadcasts" => [
        {"countryCode" => "US", "market" => "N", "network" => "ESPN"}
      ],
      "seriesStatus" => {
        "round" => 1,
        "seriesLetter" => "C",
        "gameNumberOfSeries" => 4,
        "topSeedWins" => 2,
        "bottomSeedWins" => 1,
        "neededToWin" => 4
      }
    }

    NhlApi.stubs(:offseason?).returns(false)
    NhlApi.stubs(:preseason?).returns(false)
    NhlApi.stubs(:postseason?).returns(true)
    NhlApi.stubs(:todays_game).returns(game)
    NhlApi.stubs(:team_standings).with("CAR").returns({team_name: "Carolina Hurricanes"})
    NhlApi.stubs(:team_standings).with("OTT").returns({team_name: "Ottawa Senators"})
    NhlApi.stubs(:playoff_seed_labels).returns({"CAR" => "M1", "OTT" => "WC2"})
    NhlApi.stubs(:fetch_postseason_carousel).returns(carousel_stub("C", top: "CAR", bottom: "OTT"))

    Timecop.freeze(Date.new(2026, 4, 24)) do
      @worker.perform
    end

    expected_output = <<~POST
      🗣️ It's a Carolina Hurricanes Playoff Gameday!

      Round 1, Game 4 — CAR leads 2-1

      (WC2) Ottawa Senators

      at

      (M1) Carolina Hurricanes

      ⏰ 7:00 PM EDT
      📍 Lenovo Center
      📺 ESPN
    POST

    assert_equal 1, RodTheBot::Post.jobs.size
    assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
  end

  def test_perform_postseason_gameday_series_tied
    game = {
      "id" => 2025030131,
      "gameScheduleState" => "OK",
      "startTimeUTC" => "2026-04-18T19:00:00Z",
      "venue" => {"default" => "Lenovo Center"},
      "homeTeam" => {"id" => 12, "abbrev" => "CAR", "logo" => "home.svg"},
      "awayTeam" => {"id" => 9, "abbrev" => "OTT", "logo" => "away.svg"},
      "tvBroadcasts" => [
        {"countryCode" => "US", "market" => "N", "network" => "ESPN"}
      ],
      "seriesStatus" => {
        "round" => 1,
        "seriesLetter" => "C",
        "gameNumberOfSeries" => 1,
        "topSeedWins" => 0,
        "bottomSeedWins" => 0,
        "neededToWin" => 4
      }
    }

    NhlApi.stubs(:offseason?).returns(false)
    NhlApi.stubs(:preseason?).returns(false)
    NhlApi.stubs(:postseason?).returns(true)
    NhlApi.stubs(:todays_game).returns(game)
    NhlApi.stubs(:team_standings).with("CAR").returns({team_name: "Carolina Hurricanes"})
    NhlApi.stubs(:team_standings).with("OTT").returns({team_name: "Ottawa Senators"})
    NhlApi.stubs(:playoff_seed_labels).returns({"CAR" => "M1", "OTT" => "WC2"})
    NhlApi.stubs(:fetch_postseason_carousel).returns(carousel_stub("C", top: "CAR", bottom: "OTT"))

    Timecop.freeze(Date.new(2026, 4, 18)) do
      @worker.perform
    end

    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "🗣️ It's a Carolina Hurricanes Playoff Gameday!"
    assert_includes post, "Round 1, Game 1 — Series tied 0-0"
    assert_includes post, "(WC2) Ottawa Senators"
    assert_includes post, "(M1) Carolina Hurricanes"
  end

  def test_perform_postseason_gameday_without_seed_labels
    game = {
      "id" => 2025030131,
      "gameScheduleState" => "OK",
      "startTimeUTC" => "2026-04-18T19:00:00Z",
      "venue" => {"default" => "Lenovo Center"},
      "homeTeam" => {"id" => 12, "abbrev" => "CAR", "logo" => "home.svg"},
      "awayTeam" => {"id" => 9, "abbrev" => "OTT", "logo" => "away.svg"},
      "tvBroadcasts" => [
        {"countryCode" => "US", "market" => "N", "network" => "ESPN"}
      ],
      "seriesStatus" => {
        "round" => 1,
        "seriesLetter" => "C",
        "gameNumberOfSeries" => 1,
        "topSeedWins" => 0,
        "bottomSeedWins" => 0,
        "neededToWin" => 4
      }
    }

    NhlApi.stubs(:offseason?).returns(false)
    NhlApi.stubs(:preseason?).returns(false)
    NhlApi.stubs(:postseason?).returns(true)
    NhlApi.stubs(:todays_game).returns(game)
    NhlApi.stubs(:team_standings).with("CAR").returns({team_name: "Carolina Hurricanes"})
    NhlApi.stubs(:team_standings).with("OTT").returns({team_name: "Ottawa Senators"})
    NhlApi.stubs(:playoff_seed_labels).returns({})
    NhlApi.stubs(:fetch_postseason_carousel).returns(carousel_stub("C", top: "CAR", bottom: "OTT"))

    Timecop.freeze(Date.new(2026, 4, 18)) do
      @worker.perform
    end

    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "Playoff Gameday!"
    assert_includes post, "Ottawa Senators"
    assert_includes post, "Carolina Hurricanes"
    refute_includes post, "()"
    refute_includes post, "(WC"
    refute_includes post, "(M"
  end

  def test_perform_postseason_gameday_falls_back_without_series_status
    game = {
      "id" => 2025030131,
      "gameScheduleState" => "OK",
      "startTimeUTC" => "2026-04-18T19:00:00Z",
      "venue" => {"default" => "Lenovo Center"},
      "homeTeam" => {"id" => 12, "abbrev" => "CAR", "logo" => "home.svg"},
      "awayTeam" => {"id" => 9, "abbrev" => "OTT", "logo" => "away.svg"},
      "tvBroadcasts" => [
        {"countryCode" => "US", "market" => "N", "network" => "ESPN"}
      ]
      # seriesStatus intentionally absent
    }

    NhlApi.stubs(:offseason?).returns(false)
    NhlApi.stubs(:preseason?).returns(false)
    NhlApi.stubs(:postseason?).returns(true)
    NhlApi.stubs(:todays_game).returns(game)
    NhlApi.stubs(:team_standings).with("CAR").returns({
      team_name: "Carolina Hurricanes", wins: 40, losses: 20, ot: 5,
      points: 85, division_rank: 1, division_name: "Metropolitan"
    })
    NhlApi.stubs(:team_standings).with("OTT").returns({
      team_name: "Ottawa Senators", wins: 38, losses: 25, ot: 4,
      points: 80, division_rank: 5, division_name: "Atlantic"
    })

    Timecop.freeze(Date.new(2026, 4, 18)) do
      @worker.perform
    end

    post = RodTheBot::Post.jobs.first["args"].first
    refute_includes post, "Playoff Gameday"
    assert_includes post, "🗣️ It's a Carolina Hurricanes Gameday!"
    assert_includes post, "(40-20-5, 85 points)"
  end

  def test_perform_postseason_gameday_resolves_leader_from_carousel
    game = {
      "id" => 2025030132,
      "gameScheduleState" => "OK",
      "startTimeUTC" => "2026-04-20T23:30:00Z",
      "venue" => {"default" => "Lenovo Center"},
      "homeTeam" => {"id" => 12, "abbrev" => "CAR", "logo" => "home.svg"},
      "awayTeam" => {"id" => 9, "abbrev" => "OTT", "logo" => "away.svg"},
      "tvBroadcasts" => [
        {"countryCode" => "US", "market" => "N", "network" => "ESPN"}
      ],
      "seriesStatus" => {
        "round" => 1,
        "seriesLetter" => "C",
        "gameNumberOfSeries" => 2,
        "topSeedWins" => 1,
        "bottomSeedWins" => 0,
        "neededToWin" => 4
      }
    }

    NhlApi.stubs(:offseason?).returns(false)
    NhlApi.stubs(:preseason?).returns(false)
    NhlApi.stubs(:postseason?).returns(true)
    NhlApi.stubs(:todays_game).returns(game)
    NhlApi.stubs(:team_standings).with("CAR").returns({team_name: "Carolina Hurricanes"})
    NhlApi.stubs(:team_standings).with("OTT").returns({team_name: "Ottawa Senators"})
    NhlApi.stubs(:playoff_seed_labels).returns({"CAR" => "M1", "OTT" => "WC2"})
    NhlApi.stubs(:fetch_postseason_carousel).returns(carousel_stub("C", top: "CAR", bottom: "OTT"))

    Timecop.freeze(Date.new(2026, 4, 20)) do
      @worker.perform
    end

    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "Round 1, Game 2 — CAR leads 1-0"
    refute_match(/— leads 1-0/, post, "team abbreviation must precede 'leads'")
  end

  def test_perform_postseason_gameday_without_carousel_falls_back
    game = {
      "id" => 2025030132,
      "gameScheduleState" => "OK",
      "startTimeUTC" => "2026-04-20T23:30:00Z",
      "venue" => {"default" => "Lenovo Center"},
      "homeTeam" => {"id" => 12, "abbrev" => "CAR", "logo" => "home.svg"},
      "awayTeam" => {"id" => 9, "abbrev" => "OTT", "logo" => "away.svg"},
      "tvBroadcasts" => [
        {"countryCode" => "US", "market" => "N", "network" => "ESPN"}
      ],
      "seriesStatus" => {
        "round" => 1,
        "seriesLetter" => "C",
        "gameNumberOfSeries" => 2,
        "topSeedWins" => 1,
        "bottomSeedWins" => 0,
        "neededToWin" => 4
      }
    }

    NhlApi.stubs(:offseason?).returns(false)
    NhlApi.stubs(:preseason?).returns(false)
    NhlApi.stubs(:postseason?).returns(true)
    NhlApi.stubs(:todays_game).returns(game)
    NhlApi.stubs(:team_standings).with("CAR").returns({team_name: "Carolina Hurricanes"})
    NhlApi.stubs(:team_standings).with("OTT").returns({team_name: "Ottawa Senators"})
    NhlApi.stubs(:playoff_seed_labels).returns({})
    NhlApi.stubs(:fetch_postseason_carousel).returns(nil)

    Timecop.freeze(Date.new(2026, 4, 20)) do
      @worker.perform
    end

    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "Playoff Gameday"
    assert_includes post, "Round 1, Game 2"
  end

  def teardown
    Sidekiq::Worker.clear_all
    NhlApi.unstub(:current_season)
  end

  private

  def carousel_stub(series_letter, top:, bottom:)
    {
      "rounds" => [
        {
          "series" => [
            {
              "seriesLetter" => series_letter,
              "topSeed" => {"abbrev" => top},
              "bottomSeed" => {"abbrev" => bottom}
            }
          ]
        }
      ]
    }
  end
end
