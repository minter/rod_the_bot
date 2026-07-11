require "test_helper"

class RodTheBot::PlayerStreaks::FormatterTest < ActiveSupport::TestCase
  test "uses a playoff-specific heading" do
    streak = {player_name: "#42 Player", length: 3, streak_type: "Points", total_stats: 5}

    chunk = RodTheBot::PlayerStreaks::Formatter.new.chunks([streak], season_type: "Playoffs").first

    assert chunk.start_with?("🔥 Active Streaks (Playoffs):")
    assert_includes chunk, "3-game points streak (5 total)"
  end
end
