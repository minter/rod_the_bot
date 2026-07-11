require "test_helper"

class Nhl::ScheduleClientTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "finds the team game for the requested date" do
    Nhl::ScheduleClient.stubs(:team_schedule).returns(
      "games" => [{"id" => 1, "gameDate" => "2026-01-02"}, {"id" => 2, "gameDate" => "2026-01-03"}]
    )

    game = Nhl::ScheduleClient.todays_game(date: Date.new(2026, 1, 3), team_abbreviation: "CAR")

    assert_equal 2, game["id"]
  end

  test "filters scoreboard games to the requested date" do
    Nhl::ScheduleClient.expects(:get_json).with("/score/2026-01-03").returns(
      "games" => [{"id" => 1, "gameDate" => "2026-01-02"}, {"id" => 2, "gameDate" => "2026-01-03"}]
    )

    assert_equal [2], Nhl::ScheduleClient.scores(date: Date.new(2026, 1, 3)).pluck("id")
  end
end
