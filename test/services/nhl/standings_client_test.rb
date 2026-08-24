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
end
