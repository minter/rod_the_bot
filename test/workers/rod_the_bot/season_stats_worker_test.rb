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
end
