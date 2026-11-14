require "test_helper"

class Nhl::StatsClientTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "indexes teams by numeric id" do
    Nhl::StatsClient.expects(:get_json).with("/team").returns("data" => [{"id" => 12, "fullName" => "Carolina Hurricanes"}])

    assert_equal "Carolina Hurricanes", Nhl::StatsClient.teams.dig(12, :fullName)
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

  test "normalizes situational records and derives tied-after-period records" do
    stub_situational_reports(
      {"gamesPlayed" => 20,
       "winsLeadPeriod1" => 7, "lossLeadPeriod1" => 0, "otLossLeadPeriod1" => 0,
       "winsTrailPeriod1" => 2, "lossTrailPeriod1" => 2, "otLossTrailPeriod1" => 0,
       "winsLeadPeriod2" => 9, "lossLeadPeriod2" => 0, "otLossLeadPeriod2" => 1,
       "winsTrailPeriod2" => 1, "lossTrailPeriod2" => 2, "otLossTrailPeriod2" => 0},
      {"gamesPlayed" => 20, "wins" => 15, "losses" => 3, "otLosses" => 2,
       "winsScoringFirst" => 12, "lossesScoringFirst" => 1, "otLossesScoringFirst" => 0,
       "winsTrailingFirst" => 3, "lossesTrailingFirst" => 2, "otLossesTrailingFirst" => 2}
    )

    records = Nhl::StatsClient.team_situational_records(team_id: 12, season: "20262027", game_type: 2)

    assert_equal({wins: 9, losses: 0, ot_losses: 1}, records[:leading_after_2])
    assert_equal({wins: 2, losses: 2, ot_losses: 0}, records[:trailing_after_1])
    assert_equal({wins: 6, losses: 1, ot_losses: 2}, records[:tied_after_1])
    assert_equal({wins: 5, losses: 1, ot_losses: 1}, records[:tied_after_2])
    assert_equal({wins: 12, losses: 1, ot_losses: 0}, records[:scoring_first])
    assert_equal({wins: 3, losses: 2, ot_losses: 2}, records[:trailing_first])
  end

  test "omits tied records when the two reports cover different games" do
    stub_situational_reports(
      {"gamesPlayed" => 21, "winsLeadPeriod1" => 8},
      {"gamesPlayed" => 20, "wins" => 15, "losses" => 3, "otLosses" => 2}
    )

    records = Nhl::StatsClient.team_situational_records(team_id: 12, season: "20262027", game_type: 2)

    assert_equal 8, records.dig(:leading_after_1, :wins)
    assert_not records.key?(:tied_after_1)
  end

  test "returns no situational records before the team has played" do
    stub_situational_reports(nil, nil)

    assert_empty Nhl::StatsClient.team_situational_records(team_id: 12, season: "20262027", game_type: 2)
  end

  private

  def stub_situational_reports(by_period, by_first_goal)
    filter = "seasonId=20262027 and gameTypeId=2 and teamId=12"
    {"leadingtrailing" => by_period, "scoretrailfirst" => by_first_goal}.each do |report, row|
      Nhl::StatsClient.expects(:get_json).with do |path|
        path.start_with?("/team/#{report}?") && URI.decode_www_form(URI(path).query).to_h == {"cayenneExp" => filter}
      end.returns("data" => [row].compact)
    end
  end
end
