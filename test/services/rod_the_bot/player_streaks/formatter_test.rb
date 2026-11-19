require "test_helper"

class RodTheBot::PlayerStreaks::FormatterTest < ActiveSupport::TestCase
  test "uses a playoff-specific heading" do
    streak = {player_name: "#42 Player", length: 3, streak_type: "Points", total_stats: 5}

    chunk = RodTheBot::PlayerStreaks::Formatter.new.chunks([streak], season_type: "Playoffs").first

    assert chunk.start_with?("🔥 Active Streaks (Playoffs):")
    assert_includes chunk, "3-game point streak (5 total)"
  end

  test "uses singular stat names for each streak type" do
    lines = %w[Points Goals Assists Wins].map do |type|
      RodTheBot::PlayerStreaks::Formatter.new.line({player_name: "#42 Player", length: 4, streak_type: type, total_stats: 6})
    end

    assert_equal [
      "#42 Player: 4-game point streak (6 total)\n",
      "#42 Player: 4-game goal streak (6 total)\n",
      "#42 Player: 4-game assist streak (6 total)\n",
      "#42 Player: 4-game win streak (6 total)\n"
    ], lines
  end

  test "shows a goalie point streak with its record" do
    line = RodTheBot::PlayerStreaks::Formatter.new.line({player_name: "#52 Pyotr Kochetkov", length: 10, streak_type: "Points", total_stats: 10, wins: 9, ot_losses: 1})

    assert_equal "#52 Pyotr Kochetkov: 10-game point streak (9-0-1)\n", line
  end

  test "shows a quality-start streak with its save percentage" do
    formatter = RodTheBot::PlayerStreaks::Formatter.new

    assert_equal "#52 Pyotr Kochetkov: 6 straight quality starts (.938 SV%)\n",
      formatter.line({player_name: "#52 Pyotr Kochetkov", length: 6, streak_type: "Quality Starts", total_stats: 6, saves: 150, shots_against: 160})
    assert_equal "#52 Pyotr Kochetkov: 3 straight quality starts (1.000 SV%)\n",
      formatter.line({player_name: "#52 Pyotr Kochetkov", length: 3, streak_type: "Quality Starts", total_stats: 3, saves: 75, shots_against: 75})
  end
end
