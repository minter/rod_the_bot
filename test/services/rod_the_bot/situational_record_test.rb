require "test_helper"

class RodTheBot::SituationalRecordTest < ActiveSupport::TestCase
  RECORDS = {
    leading_after_1: {wins: 7, losses: 0, ot_losses: 0},
    trailing_after_1: {wins: 2, losses: 2, ot_losses: 0},
    tied_after_1: {wins: 6, losses: 1, ot_losses: 2},
    leading_after_2: {wins: 9, losses: 0, ot_losses: 1},
    trailing_after_2: {wins: 0, losses: 0, ot_losses: 0},
    scoring_first: {wins: 12, losses: 1, ot_losses: 0},
    trailing_first: {wins: 3, losses: 2, ot_losses: 2}
  }.freeze

  def record(game_type: 2, records: RECORDS)
    RodTheBot::SituationalRecord.new(records: records, team_name: "Hurricanes", game_type: game_type)
  end

  test "describes the record when leading after a period" do
    assert_equal "The Hurricanes are 9-0-1 when leading after two periods this season.",
      record.after_period(2, team_score: 3, opponent_score: 1)
  end

  test "describes the record when trailing or tied after a period" do
    assert_equal "The Hurricanes are 2-2-0 when trailing after one period this season.",
      record.after_period(1, team_score: 0, opponent_score: 1)
    assert_equal "The Hurricanes are 6-1-2 when tied after one period this season.",
      record.after_period(1, team_score: 2, opponent_score: 2)
  end

  test "describes the record by first goal" do
    assert_equal "The Hurricanes are 12-1-0 when scoring first this season.", record.first_goal(scored_by_team: true)
    assert_equal "The Hurricanes are 3-2-2 when allowing the first goal this season.", record.first_goal(scored_by_team: false)
  end

  test "uses a win-loss record in the playoffs" do
    assert_equal "The Hurricanes are 9-0 when leading after two periods this postseason.",
      record(game_type: 3).after_period(2, team_score: 3, opponent_score: 1)
  end

  test "says nothing without games in the situation" do
    assert_nil record.after_period(2, team_score: 1, opponent_score: 3)
    assert_nil record(records: {}).first_goal(scored_by_team: true)
    assert_nil record(records: nil).after_period(1, team_score: 1, opponent_score: 0)
  end

  test "says nothing after the third period or overtime" do
    assert_nil record.after_period(3, team_score: 2, opponent_score: 2)
    assert_nil record.after_period(4, team_score: 2, opponent_score: 2)
  end
end
