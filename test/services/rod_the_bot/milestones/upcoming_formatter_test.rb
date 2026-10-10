require "test_helper"

class RodTheBot::Milestones::UpcomingFormatterTest < ActiveSupport::TestCase
  Entry = RodTheBot::Milestones::Upcoming::Entry

  setup { @formatter = RodTheBot::Milestones::UpcomingFormatter.new }

  test "formats lines with urgency and pluralization" do
    assert_equal "🔥 #20 Sebastian Aho: 1 assist away from 50\n", @formatter.line("#20 Sebastian Aho", Entry.new(player_id: 1, type: "assist", target: 50, remaining: 1))
    assert_equal "⚡ #31 Frederik Andersen: 2 wins away from 300\n", @formatter.line("#31 Frederik Andersen", Entry.new(player_id: 1, type: "win", target: 300, remaining: 2))
    assert_equal "📈 #24 Logan Stankoven: 4 points away from 100\n", @formatter.line("#24 Logan Stankoven", Entry.new(player_id: 1, type: "point", target: 100, remaining: 4))
  end

  test "labels playoff headers" do
    assert_equal "🎯 Upcoming Milestones:\n\n", @formatter.header(playoffs: false)
    assert_equal "🎯 Upcoming Milestones (Playoffs):\n\n", @formatter.header(playoffs: true)
  end
end
