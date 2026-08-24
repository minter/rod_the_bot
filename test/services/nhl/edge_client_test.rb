require "test_helper"

class Nhl::EdgeClientTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "fetches current EDGE data through the configured endpoint" do
    Nhl::EdgeClient.expects(:get_json).with("/edge/team-skating-speed-detail/12/now").returns({"speed" => 1})

    assert_equal({"speed" => 1}, Nhl::EdgeClient.fetch_team_skating_speed_detail(12))
  end

  test "includes season and game type in endpoint and cache identity" do
    Nhl::EdgeClient.expects(:get_json).with("/edge/goalie-detail/42/20252026/2").returns({"goalie" => 1})

    assert_equal({"goalie" => 1}, Nhl::EdgeClient.fetch_goalie_detail(42, season: 20252026, game_type: 2))
  end

  test "derives an explicit EDGE period from the game id" do
    Nhl::EdgeClient.expects(:get_json).with("/edge/team-skating-speed-detail/12/20262027/2").returns({"speed" => 1})

    assert_equal({"speed" => 1}, Nhl::EdgeClient.fetch_team_skating_speed_detail(12, game_id: 2026020018))
  end

  test "treats missing explicit EDGE data as temporarily unavailable" do
    Rails.logger.expects(:warn).with("EDGE data unavailable for team-skating-speed-detail/12/20262027/2")
    Nhl::EdgeClient.expects(:get_json).raises(
      Nhl::RequestError,
      "API request failed for /edge/team-skating-speed-detail/12/20262027/2: HTTP 404"
    )

    assert_nil Nhl::EdgeClient.fetch_team_skating_speed_detail(12, game_id: 2026020018)
  end
end
