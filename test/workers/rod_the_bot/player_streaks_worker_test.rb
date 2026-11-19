require "test_helper"

class RodTheBot::PlayerStreaksWorkerTest < ActiveSupport::TestCase
  KOCHETKOV = 8481611
  AHO = 8478427

  def setup
    Sidekiq::Worker.clear_all
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
    Nhl::SeasonCalendar.stubs(:preseason?).returns(false)
    Nhl::SeasonCalendar.stubs(:postseason?).returns(false)
    Nhl::SeasonCalendar.stubs(:current_season).returns("20262027")
    Nhl::PlayerDirectory.stubs(:for_team).with("CAR").returns(Nhl::PlayerDirectory.new([
      Nhl::PlayerIdentity.new(id: KOCHETKOV, first_name: "Pyotr", last_name: "Kochetkov", sweater_number: 52, team_abbreviation: "CAR"),
      Nhl::PlayerIdentity.new(id: AHO, first_name: "Sebastian", last_name: "Aho", sweater_number: 20, team_abbreviation: "CAR")
    ]))
  end

  def teardown
    Sidekiq::Worker.clear_all
  end

  test "reports goalie streaks for roster goalies" do
    Nhl::Roster.stubs(:for).with("CAR").returns(
      KOCHETKOV => {id: KOCHETKOV, positionCode: "G"},
      AHO => {id: AHO, positionCode: "C"}
    )
    Nhl::PlayerClient.stubs(:game_log).with(KOCHETKOV.to_s).returns(Array.new(10) { {"decision" => "W", "gamesStarted" => 1, "shotsAgainst" => 30, "goalsAgainst" => 1} } + [{"decision" => "L", "gamesStarted" => 1, "shotsAgainst" => 20, "goalsAgainst" => 5}])
    Nhl::PlayerClient.stubs(:game_log).with(AHO.to_s).returns(Array.new(3) { {"points" => 1, "goals" => 0, "assists" => 1} } + [{"points" => 0}])

    RodTheBot::PlayerStreaksWorker.new.perform

    assert_equal 1, RodTheBot::Post.jobs.size
    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "#52 Pyotr Kochetkov: 10-game win streak (10 total)"
    assert_includes post, "#52 Pyotr Kochetkov: 10 straight quality starts (.967 SV%)"
    assert_includes post, "#20 Sebastian Aho: 3-game point streak (3 total)"
  end
end
