require "test_helper"

class RodTheBot::EdgeHotZonesTest < ActiveSupport::TestCase
  test "returns zones at or above the elite percentile sorted by percentile" do
    zones = [
      {"area" => "L Circle", "goals" => 3, "goalsPercentile" => 0.85},
      {"area" => "High Slot", "goals" => 3, "goalsPercentile" => 1.0},
      {"area" => "L Point", "goals" => 1, "goalsPercentile" => 0.79}
    ]

    assert_equal ["High Slot", "L Circle"], RodTheBot::EdgeHotZones.elite(zones).map { |z| z["area"] }
  end

  test "excludes zones where the player has not scored" do
    zones = [
      {"area" => "High Slot", "goals" => 3, "goalsPercentile" => 1.0},
      {"area" => "R Corner", "goals" => 0, "goalsPercentile" => 1.0},
      {"area" => "Behind Net", "goals" => nil, "goalsPercentile" => 1.0}
    ]

    assert_equal ["High Slot"], RodTheBot::EdgeHotZones.elite(zones).map { |z| z["area"] }
  end

  test "ignores zones without a percentile and handles missing details" do
    assert_empty RodTheBot::EdgeHotZones.elite([{"area" => "Slot", "goals" => 2}])
    assert_empty RodTheBot::EdgeHotZones.elite(nil)
  end
end
