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

  test "skater game log matches the NHL API contract" do
    VCR.use_cassette("nhl_player_game_log_skater_8478427_20252026_2") do
      Nhl::SeasonCalendar.stubs(:current_season).returns("20252026")
      Nhl::SeasonCalendar.stubs(:postseason?).returns(false)

      games = Nhl::PlayerClient.game_log(8478427, limit: 10)

      assert_equal 10, games.length
      assert games.all? { |game| %w[gameId gameDate goals assists points].all? { |key| game.key?(key) } }
      assert games.each_cons(2).all? { |newer, older| newer["gameDate"] >= older["gameDate"] }
    end
  end

  test "goalie game log uses real NHL decision codes" do
    VCR.use_cassette("nhl_player_game_log_goalie_8479496_20252026_2") do
      Nhl::SeasonCalendar.stubs(:current_season).returns("20252026")
      Nhl::SeasonCalendar.stubs(:postseason?).returns(false)

      games = Nhl::PlayerClient.game_log(8479496, limit: 40)
      decisions = games.filter_map { |game| game["decision"] }.uniq

      assert_includes decisions, "W"
      assert_includes decisions, "L"
      assert_includes decisions, "O"
      assert games.any? { |game| game["gamesStarted"] == 0 && game["decision"].nil? }
    end
  end

  test "career totals match the NHL player landing contract" do
    VCR.use_cassette("nhl_player_landing_career_8482093") do
      totals = Nhl::PlayerClient.career_totals(8482093)

      assert_operator totals["gamesPlayed"], :>, 0
      assert %w[goals assists points].all? { |stat| totals.key?(stat) }
    end
  end

  test "returns club stats from the current-season endpoint" do
    Nhl::PlayerClient.expects(:get_json).with("/club-stats/CAR/now").returns(
      "season" => 20252026,
      "skaters" => [],
      "goalies" => []
    )

    assert_equal 20252026, Nhl::PlayerClient.club_stats("CAR")["season"]
  end
end
