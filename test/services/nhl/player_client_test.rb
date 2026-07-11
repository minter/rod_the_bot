require "test_helper"

class Nhl::PlayerClientTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "limits the current season game log" do
    Nhl::SeasonCalendar.stubs(:current_season).returns("20252026")
    Nhl::SeasonCalendar.stubs(:postseason?).returns(false)
    Nhl::PlayerClient.expects(:get_json).with("/player/42/game-log/20252026/2").returns(
      "gameLog" => [{"gameId" => 1}, {"gameId" => 2}]
    )

    assert_equal [1], Nhl::PlayerClient.game_log(42, limit: 1).pluck("gameId")
  end
end
