require "test_helper"

class RodTheBot::Scheduling::GamedayPostTest < ActiveSupport::TestCase
  test "formats a regular-season game with records" do
    team = {team_name: "Hurricanes", abbrev: "CAR", wins: 10, losses: 5, ot: 1, points: 21, division_rank: 2, division_name: "Metropolitan"}
    opponent = team.merge(team_name: "Devils", abbrev: "NJD")

    post = RodTheBot::Scheduling::GamedayPost.new.build(
      game: {"venue" => {"default" => "Lenovo Center"}}, away: opponent, home: team,
      tracked: team, time: "7:00 PM EST", television: "ESPN", preseason: false, postseason: false
    )

    assert_includes post, "It's a Hurricanes Gameday!"
    assert_includes post, "(10-5-1, 21 points)"
    assert_includes post, "2nd in the Metropolitan"
  end
end
