require "test_helper"

class RodTheBot::Milestones::FranchiseRankTest < ActiveSupport::TestCase
  TOTALS = [
    {player_id: 1, name: "Ron Francis", goals: 382, assists: 793, points: 1175},
    {player_id: 2, name: "Eric Staal", goals: 322, assists: 453, points: 775},
    {player_id: 3, name: "Sebastian Aho", goals: 322, assists: 417, points: 739},
    {player_id: 4, name: "Kevin Dineen", goals: 250, assists: 294, points: 544},
    {player_id: 5, name: "Jeff O'Neill", goals: 198, assists: 218, points: 416},
    {player_id: 6, name: "Jordan Staal", goals: 197, assists: 301, points: 499}
  ].freeze

  def rank(in_game = {}, totals: TOTALS)
    RodTheBot::Milestones::FranchiseRank.new(
      totals: totals,
      in_game: ->(player_id, stat) { in_game.fetch([player_id, stat], 0) }
    )
  end

  test "reports passing a player who was level before the goal" do
    event = rank({[3, "goals"] => 1}).event(3, "goals")

    assert_equal 323, event.total
    assert_equal 2, event.rank
    assert_equal ["Eric Staal"], event.passed
    assert_empty event.tied
    assert_equal "Ron Francis", event.next_up.name
    assert_equal 382, event.next_up.total
  end

  test "reports drawing level with a player" do
    event = rank({[6, "goals"] => 1}).event(6, "goals")

    assert_equal 198, event.total
    assert_equal 5, event.rank
    assert_equal ["Jeff O'Neill"], event.tied
  end

  test "counts what teammates on the list have done in the same game" do
    event = rank({[6, "goals"] => 2, [3, "goals"] => 1}).event(6, "goals")

    assert_equal 199, event.total
    assert_equal ["Jeff O'Neill"], event.passed
    assert_equal 5, event.rank
  end

  test "has no next player to chase at the top of the list" do
    totals = [TOTALS[1], TOTALS[2]]
    event = rank({[3, "goals"] => 1}, totals: totals).event(3, "goals")

    assert_equal 1, event.rank
    assert_nil event.next_up
  end

  test "reports nothing when the order is unchanged" do
    assert_nil rank({[4, "goals"] => 1}).event(4, "goals")
  end

  test "reports nothing outside the top ten" do
    totals = (1..12).map { |id| {player_id: id, name: "Player #{id}", goals: 100 - id, assists: 0, points: 100 - id} }

    assert_nil rank({[12, "goals"] => 1}, totals: totals).event(12, "goals")
    assert_equal 10, rank({[11, "goals"] => 1}, totals: totals).event(11, "goals").rank
  end

  test "handles a player with no franchise totals yet" do
    assert_nil rank({[99, "goals"] => 1}).event(99, "goals")
  end
end
