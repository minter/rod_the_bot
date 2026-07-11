require "test_helper"

class RodTheBot::Milestones::FormatterTest < ActiveSupport::TestCase
  test "formats a milestone event" do
    event = RodTheBot::Milestones::Evaluator::Event.new(type: "goal", value: 100, first: false)

    assert_includes RodTheBot::Milestones::Formatter.new.format("#42 Player", event), "100 career goals"
  end
end
