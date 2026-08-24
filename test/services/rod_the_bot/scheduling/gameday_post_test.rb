require "test_helper"

class RodTheBot::Scheduling::GamedayPostTest < ActiveSupport::TestCase
  test "formats a regular-season game with records" do
    team = {team_name: "Hurricanes", abbrev: "CAR", wins: 10, losses: 5, ot: 1, points: 21, division_rank: 2, division_name: "Metropolitan"}
    opponent = team.merge(team_name: "Devils", abbrev: "NJD")

    post = RodTheBot::Scheduling::GamedayPost.new.build(
      game: {"venue" => {"default" => "Lenovo Center"}}, away: opponent, home: team,
      tracked: team, starts_at: Time.iso8601("2026-11-12T00:00:00Z"), time_zone: "America/New_York",
      television: "ESPN", preseason: false, postseason: false
    )

    assert_includes post, "It's a Hurricanes Gameday!"
    assert_includes post, "(10-5-1, 21 points)"
    assert_includes post, "2nd in the Metropolitan"
  end

  test "formats special events with both configured and venue-local times" do
    team = {team_name: "Carolina Hurricanes", abbrev: "CAR"}
    opponent = {team_name: "Seattle Kraken", abbrev: "SEA"}
    game = {
      "venue" => {"default" => "Veikkaus Arena"},
      "venueTimezone" => "Europe/Helsinki",
      "specialEvent" => {"name" => {"default" => "2026 NHL Global Series"}}
    }

    post = RodTheBot::Scheduling::GamedayPost.new.build(
      game: game, away: team, home: opponent, tracked: team,
      starts_at: Time.iso8601("2026-11-12T17:00:00Z"), time_zone: "America/New_York",
      television: "TBD", preseason: false, postseason: false
    )

    assert_includes post, "🌍 2026 NHL Global Series"
    assert_includes post, "Carolina Hurricanes\n\nat\n\nSeattle Kraken"
    assert_includes post, "⏰ 12:00 PM EST"
    assert_includes post, "🌐 7:00 PM EET local time"
    assert_includes post, "📍 Veikkaus Arena"
  end
end
