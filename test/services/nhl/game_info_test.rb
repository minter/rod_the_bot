require "test_helper"

class Nhl::GameInfoTest < ActiveSupport::TestCase
  test "normalizes completed season-series games across home and away assignments" do
    Nhl::GameClient.stubs(:right_rail).with(2026021334).returns(
      "seasonSeries" => [
        series_game(1, "2026-10-01", away: team(12, "CAR", 3), home: team(13, "FLA", 4), outcome: "SO"),
        series_game(2, "2027-01-21", away: team(13, "FLA", 2), home: team(12, "CAR", 5)),
        series_game(3, "2027-04-10", away: team(12, "CAR"), home: team(13, "FLA"))
      ]
    )

    result = Nhl::GameInfo.season_series(2026021334, team_id: 12)

    assert_equal "CAR", result[:tracked_abbrev]
    assert_equal "FLA", result[:opponent_abbrev]
    assert_equal 1, result[:tracked_wins]
    assert_equal 1, result[:opponent_wins]
    assert_equal 2, result[:completed_meetings]
    assert_equal 3, result[:total_meetings]
    assert_equal({
      date: "2027-01-21", away_abbrev: "FLA", away_score: 2,
      home_abbrev: "CAR", home_score: 5, last_period_type: "REG", overtime_periods: nil
    }, result[:last_meeting])
  end

  test "omits season-series context before a game has been completed" do
    Nhl::GameClient.stubs(:right_rail).returns(
      "seasonSeries" => [series_game(1, "2026-09-29", away: team(13, "FLA"), home: team(12, "CAR"))]
    )

    assert_nil Nhl::GameInfo.season_series(2026020001, team_id: 12)
  end

  private

  def series_game(id, date, away:, home:, outcome: "REG")
    {
      "id" => id,
      "gameDate" => date,
      "awayTeam" => away,
      "homeTeam" => home,
      "gameOutcome" => {"lastPeriodType" => outcome}
    }
  end

  def team(id, abbrev, score = nil)
    {"id" => id, "abbrev" => abbrev}.tap do |data|
      data["score"] = score unless score.nil?
    end
  end
end
