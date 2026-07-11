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
end
