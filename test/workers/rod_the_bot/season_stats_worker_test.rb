require "test_helper"

class RodTheBot::SeasonStatsWorkerTest < ActiveSupport::TestCase
  def setup
    @worker = RodTheBot::SeasonStatsWorker.new
    @team_abbreviation = ENV["NHL_TEAM_ABBREVIATION"]
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
  end

  def teardown
    ENV["NHL_TEAM_ABBREVIATION"] = @team_abbreviation
  end

  def test_top_skaters_rejects_zero_values
    stats = {
      1 => {name: "Scorer", goals: 30, points: 60, pim: 22},
      2 => {name: "Middle", goals: 15, points: 40, pim: 0},
      3 => {name: "Zero Goals", goals: 0, points: 5, pim: 8},
      4 => {name: "Zero PIM", goals: 10, points: 20, pim: 0},
      5 => {name: "Zero Everything", goals: 0, points: 0, pim: 0}
    }

    pim_leaders = @worker.send(:top_skaters, stats, :pim)
    names = pim_leaders.map { |_, v| v[:name] }
    assert_equal ["Scorer", "Zero Goals"], names

    goal_leaders = @worker.send(:top_skaters, stats, :goals)
    goal_names = goal_leaders.map { |_, v| v[:name] }
    assert_equal ["Scorer", "Middle", "Zero PIM"], goal_names
  end

  def test_top_skaters_returns_empty_when_all_zero
    stats = {
      1 => {name: "A", pim: 0},
      2 => {name: "B", pim: 0}
    }
    assert_empty @worker.send(:top_skaters, stats, :pim)
  end

  def test_top_skaters_caps_at_five
    stats = (1..10).each_with_object({}) { |i, h| h[i] = {name: "P#{i}", goals: i} }
    leaders = @worker.send(:top_skaters, stats, :goals)
    assert_equal 5, leaders.length
    assert_equal ["P10", "P9", "P8", "P7", "P6"], leaders.map { |_, v| v[:name] }
  end

  # club-stats carries no sweaterNumber, so numbers must come from the team roster.
  test "collect_roster_stats takes sweater numbers from the team directory" do
    Nhl::PlayerClient.stubs(:club_stats).returns(club_stats_response)
    Nhl::PlayerDirectory.expects(:for_team).with("CAR").returns(
      Nhl::PlayerDirectory.new([
        Nhl::PlayerIdentity.new(id: 8475235, first_name: "Nicolas", last_name: "Deslauriers", sweater_number: 44),
        Nhl::PlayerIdentity.new(id: 8479496, first_name: "Pyotr", last_name: "Kochetkov", sweater_number: 52)
      ])
    )

    skaters, goalies = @worker.collect_roster_stats(season: "20262027", game_type: 2)

    assert_equal "#44 Nicolas Deslauriers", skaters[8475235][:name]
    assert_equal "#52 Pyotr Kochetkov", goalies[8479496][:name]
  end

  test "collect_roster_stats omits the number for players no longer on the roster" do
    Nhl::PlayerClient.stubs(:club_stats).returns(club_stats_response)
    Nhl::PlayerDirectory.stubs(:for_team).returns(Nhl::PlayerDirectory.new([]))

    skaters, goalies = @worker.collect_roster_stats(season: "20262027", game_type: 2)

    assert_equal "Nicolas Deslauriers", skaters[8475235][:name]
    assert_equal "Pyotr Kochetkov", goalies[8479496][:name]
  end

  test "perform does not fetch stats during preseason" do
    Nhl::SeasonCalendar.expects(:preseason?).returns(true)
    Nhl::PlayerClient.expects(:club_stats).never

    @worker.perform("Carolina Hurricanes")

    assert_empty RodTheBot::Post.jobs
  end

  test "perform requests current season stats explicitly" do
    Nhl::SeasonCalendar.expects(:preseason?).returns(false)
    Nhl::SeasonCalendar.expects(:current_season).returns("20262027")
    Nhl::SeasonCalendar.expects(:postseason?).returns(false)
    Nhl::PlayerClient.expects(:club_stats).with(
      "CAR",
      season: "20262027",
      game_type: 2
    ).returns(
      "season" => "20262027",
      "gameType" => 2,
      "skaters" => [],
      "goalies" => []
    )

    @worker.perform("Carolina Hurricanes")

    assert_empty RodTheBot::Post.jobs
  end

  test "perform skips leaderboards that have no qualifying skaters" do
    Nhl::SeasonCalendar.stubs(:preseason?).returns(false)
    Nhl::SeasonCalendar.stubs(:current_season).returns("20262027")
    Nhl::SeasonCalendar.stubs(:postseason?).returns(false)
    Nhl::PlayerClient.stubs(:club_stats).returns(club_stats_response)
    Nhl::PlayerDirectory.stubs(:for_team).returns(Nhl::PlayerDirectory.new([]))
    team_summary = Hash.new(0.5).merge("teamId" => ENV["NHL_TEAM_ID"].to_i)
    Nhl::StatsClient.stubs(:team_summary).returns([team_summary])

    @worker.perform("Carolina Hurricanes")

    posts = RodTheBot::Post.jobs.map { |job| job["args"].first }
    assert_equal 5, posts.length
    assert posts.any? { |post| post.include?("penalty minute leaders") }
    assert posts.any? { |post| post.include?("time on ice leaders") }
    assert posts.none? { |post| post.match?(/points leaders|goal scoring leaders|assist leaders/) }
  end

  private

  def club_stats_response
    {
      "season" => "20262027",
      "gameType" => 2,
      "skaters" => [{
        "playerId" => 8475235,
        "firstName" => {"default" => "Nicolas"},
        "lastName" => {"default" => "Deslauriers"},
        "gamesPlayed" => 1,
        "goals" => 0,
        "assists" => 0,
        "points" => 0,
        "plusMinus" => 0,
        "penaltyMinutes" => 5,
        "avgTimeOnIcePerGame" => 301.0
      }],
      "goalies" => [{
        "playerId" => 8479496,
        "firstName" => {"default" => "Pyotr"},
        "lastName" => {"default" => "Kochetkov"},
        "gamesPlayed" => 1,
        "wins" => 1,
        "losses" => 0,
        "overtimeLosses" => 0,
        "savePercentage" => 0.92,
        "goalsAgainstAverage" => 2.0
      }]
    }
  end
end
