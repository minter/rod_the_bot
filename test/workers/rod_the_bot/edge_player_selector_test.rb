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
end
