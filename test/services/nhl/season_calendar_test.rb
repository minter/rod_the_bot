require "test_helper"

class Nhl::SeasonCalendarTest < ActiveSupport::TestCase
  setup do
    Nhl::SeasonCalendar.stubs(:schedule).returns(
      "preSeasonStartDate" => "2025-09-20",
      "regularSeasonStartDate" => "2025-10-07",
      "regularSeasonEndDate" => "2026-04-16",
      "playoffEndDate" => "2026-06-22",
      "numberOfGames" => 1
    )
  end

  test "identifies preseason" do
    assert Nhl::SeasonCalendar.preseason?(today: Date.new(2025, 9, 25))
    refute Nhl::SeasonCalendar.preseason?(today: Date.new(2025, 10, 7))
  end

  test "identifies postseason" do
    refute Nhl::SeasonCalendar.postseason?(today: Date.new(2026, 4, 16))
    assert Nhl::SeasonCalendar.postseason?(today: Date.new(2026, 4, 17))
  end

  test "identifies offseason" do
    assert Nhl::SeasonCalendar.offseason?(today: Date.new(2025, 7, 1))
    refute Nhl::SeasonCalendar.offseason?(today: Date.new(2025, 10, 7))
  end
end
