require "test_helper"

class RodTheBot::Milestones::EvaluatorTest < ActiveSupport::TestCase
  test "reports both goal and point milestones for a scorer" do
    totals = stub(evaluator_totals: true)
    totals.stubs(:for).with(42, "goals").returns(100)
    totals.stubs(:for).with(42, "points").returns(200)

    events = RodTheBot::Milestones::Evaluator.new(totals: totals).scorer(42)

    assert_equal %w[goal point], events.map(&:type)
  end

  test "deduplicates first goal and first point" do
    totals = stub(evaluator_totals: true)
    totals.stubs(:for).returns(1)

    events = RodTheBot::Milestones::Evaluator.new(totals: totals).scorer(42)

    assert_equal ["goal"], events.map(&:type)
    assert events.first.first
  end
end
