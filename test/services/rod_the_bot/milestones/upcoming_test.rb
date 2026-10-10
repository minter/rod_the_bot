require "test_helper"

class RodTheBot::Milestones::UpcomingTest < ActiveSupport::TestCase
  def entries(totals, goalie: false)
    RodTheBot::Milestones::Upcoming.new(career_totals: ->(_player_id) { totals }).for(1, goalie: goalie)
  end

  test "reports the next skater milestone within reach" do
    result = entries({"goals" => 45, "assists" => 55, "points" => 96, "gamesPlayed" => 188})

    assert_equal [RodTheBot::Milestones::Upcoming::Entry.new(player_id: 1, type: "point", target: 100, remaining: 4)], result
  end

  test "looks past a milestone the player already reached" do
    assert_empty entries({"goals" => 45, "assists" => 55, "points" => 100, "gamesPlayed" => 188})
  end

  test "applies per-type reach limits" do
    within = entries({"goals" => 97, "assists" => 45, "gamesPlayed" => 98})
    beyond = entries({"goals" => 96, "assists" => 44, "gamesPlayed" => 97})

    assert_equal %w[goal assist game], within.map(&:type)
    assert_empty beyond
  end

  test "checks goalie stats instead of skater stats" do
    result = entries({"wins" => 298, "shutouts" => 29, "gamesPlayed" => 552, "goals" => 0, "points" => 49}, goalie: true)

    assert_equal [["win", 300, 2], ["shutout", 30, 1]], result.map { |entry| [entry.type, entry.target, entry.remaining] }
  end

  test "does not preview first-career milestones" do
    assert_empty entries({"goals" => 0, "assists" => 0, "points" => 0, "gamesPlayed" => 0})
  end

  test "treats missing career totals as no history" do
    assert_empty entries({})
  end
end
