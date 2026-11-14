require "test_helper"

class RodTheBot::EdgePlayerSelectorTest < ActiveSupport::TestCase
  class Selector
    include RodTheBot::EdgePlayerSelector
  end

  def setup
    @original_env = ENV.to_h
    ENV["TIME_ZONE"] = "America/New_York"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
    ENV["NHL_TEAM_ID"] = "12"
  end

  def teardown
    ENV.replace(@original_env)
  end

  test "looks back from the configured time zone's date rather than the host's" do
    ENV["TZ"] = "America/Los_Angeles"
    requested_dates = []
    Nhl::ScheduleClient.stubs(:team_schedule).with { |date:| requested_dates << date }.returns("games" => [])

    # Half past midnight Eastern is still the previous evening on a Pacific host.
    Timecop.freeze(Time.use_zone("America/New_York") { Time.zone.local(2026, 1, 10, 0, 30) }) do
      assert_empty Selector.new.select_eligible_players(criteria: :high_workload)
    end

    assert_equal "2026-01-10", requested_dates.first
    assert_equal "2026-01-03", requested_dates.second
  end

  test "uses the most recent completed games when they span more than one week" do
    this_week = [game(5, "2026-01-06", "OFF"), game(6, "2026-01-08", "FINAL"), game(7, "2026-01-10", "FUT")]
    last_week = [game(2, "2025-12-30", "OFF"), game(3, "2026-01-01", "OFF"), game(4, "2026-01-03", "OFF")]
    Nhl::ScheduleClient.stubs(:team_schedule).with(date: "2026-01-09").returns("games" => this_week)
    Nhl::ScheduleClient.stubs(:team_schedule).with(date: "2026-01-02").returns("games" => last_week)

    Timecop.freeze(Time.use_zone("America/New_York") { Time.zone.local(2026, 1, 9, 12) }) do
      assert_equal [4, 5, 6], Selector.new.send(:get_recent_game_ids, 3)
    end
  end

  private

  def game(id, date, state)
    {"id" => id, "gameDate" => date, "startTimeUTC" => "#{date}T00:00:00Z", "gameState" => state}
  end
end
