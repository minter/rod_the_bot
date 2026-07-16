require "test_helper"

class Nhl::StatsClientTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "indexes teams by numeric id" do
    Nhl::StatsClient.expects(:get_json).with("/team").returns("data" => [{"id" => 12, "fullName" => "Carolina Hurricanes"}])

    assert_equal "Carolina Hurricanes", Nhl::StatsClient.teams.dig(12, :fullName)
  end

  test "returns empty milestone data when the API is unavailable" do
    Nhl::StatsClient.stubs(:get_json).raises(Nhl::RequestError, "unavailable")

    assert_equal({}, Nhl::StatsClient.skater_milestones)
  end

  test "returns normalized team summary rows" do
    Nhl::StatsClient.expects(:get_json).with do |path|
      path.start_with?("/team/summary?") &&
        URI.decode_www_form(URI(path).query).to_h == {
          "sort" => "goalsForPerGame",
          "cayenneExp" => "seasonId=20252026 and gameTypeId=2"
        }
    end.returns("data" => [{"teamId" => 12, "goalsForPerGame" => 3.4}])

    rows = Nhl::StatsClient.team_summary(season: 20252026, game_type: 2, sort: "goalsForPerGame")

    assert_equal 12, rows.first["teamId"]
  end

  test "returns normalized shift chart rows" do
    Nhl::StatsClient.expects(:get_json).with do |path|
      path.start_with?("/shiftcharts?") &&
        URI.decode_www_form(URI(path).query).to_h["cayenneExp"] == "gameId=2025020660"
    end.returns("data" => [{"playerId" => 1}])

    assert_equal [{"playerId" => 1}], Nhl::StatsClient.shift_charts(2025020660)
  end
end
