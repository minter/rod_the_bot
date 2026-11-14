require "test_helper"

class RodTheBot::Milestones::FranchiseRankFormatterTest < ActiveSupport::TestCase
  Event = RodTheBot::Milestones::FranchiseRank::Event
  Entry = RodTheBot::Milestones::FranchiseRank::Entry

  def format(**attributes)
    defaults = {stat: "goals", total: 323, rank: 2, tied: [], passed: [], next_up: nil}
    RodTheBot::Milestones::FranchiseRankFormatter.new.format("#20 Sebastian Aho", Event.new(**defaults, **attributes))
  end

  test "formats passing a player" do
    assert_equal(
      "📈 #20 Sebastian Aho (323) passes Eric Staal for sole possession of 2nd on the franchise's all-time goals list. Next up: Ron Francis (382).",
      format(passed: ["Eric Staal"], next_up: Entry.new(name: "Ron Francis", total: 382))
    )
  end

  test "formats taking over first place" do
    assert_equal(
      "📈 #20 Sebastian Aho (383) passes Ron Francis for sole possession of 1st on the franchise's all-time goals list.",
      format(total: 383, rank: 1, passed: ["Ron Francis"])
    )
  end

  test "formats a tie with several players" do
    assert_equal(
      "📈 #20 Sebastian Aho (198) ties Jeff O'Neill and Jordan Staal for 7th on the franchise's all-time points list.",
      format(stat: "points", total: 198, rank: 7, tied: ["Jeff O'Neill", "Jordan Staal"], passed: ["Geoff Sanderson"])
    )
  end
end
