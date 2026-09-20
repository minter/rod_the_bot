require "test_helper"

class Nhl::StandingsClientTest < ActiveSupport::TestCase
  test "rejects standings from another season" do
    Nhl::StandingsClient.stubs(:standings).returns(
      "standings" => [
        {
          "teamAbbrev" => {"default" => "CAR"},
          "teamName" => {"default" => "Carolina Hurricanes"},
          "seasonId" => 20252026
        }
      ]
    )
    Rails.logger.expects(:warn).with(
      "Standings season mismatch for CAR: expected 20262027, got 20252026"
    )

    assert_equal(
      {team_name: "Carolina Hurricanes", season_id: 20252026},
      Nhl::StandingsClient.team("CAR", season: 20262027)
    )
  end

  test "current_standings returns entries when the season matches" do
    entries = [{"teamAbbrev" => {"default" => "CAR"}, "seasonId" => 20262027}]
    Nhl::StandingsClient.stubs(:standings).returns("standings" => entries)
    Nhl::SeasonCalendar.stubs(:current_season).returns("20262027")

    assert_equal entries, Nhl::StandingsClient.current_standings
  end

  test "current_standings rejects a previous season's final standings" do
    # /standings/now resolves to last season's final day during the preseason.
    Nhl::StandingsClient.stubs(:standings).returns(
      "standings" => [{"teamAbbrev" => {"default" => "CAR"}, "seasonId" => 20252026, "points" => 113}]
    )
    Nhl::SeasonCalendar.stubs(:current_season).returns("20262027")

    assert_empty Nhl::StandingsClient.current_standings
  end

  test "current_standings returns empty when standings are empty" do
    Nhl::StandingsClient.stubs(:standings).returns("standings" => [])
    Nhl::SeasonCalendar.expects(:current_season).never

    assert_empty Nhl::StandingsClient.current_standings
  end

  test "current_standings rejects entries that omit seasonId" do
    Nhl::StandingsClient.stubs(:standings).returns(
      "standings" => [{"teamAbbrev" => {"default" => "CAR"}}]
    )
    Nhl::SeasonCalendar.stubs(:current_season).returns("20262027")

    assert_empty Nhl::StandingsClient.current_standings
  end
end
