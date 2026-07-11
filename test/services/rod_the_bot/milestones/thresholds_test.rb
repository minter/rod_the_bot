require "test_helper"

class RodTheBot::Milestones::ThresholdsTest < ActiveSupport::TestCase
  test "distinguishes milestone boundaries" do
    assert RodTheBot::Milestones::Thresholds.include?("goal", 100)
    refute RodTheBot::Milestones::Thresholds.include?("goal", 99)
    refute RodTheBot::Milestones::Thresholds.include?("assist", 1)
    assert RodTheBot::Milestones::Thresholds.include?("shutout", 10)
  end
end
