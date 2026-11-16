require "test_helper"

class RodTheBot::EdgeRecap::FormatterTest < ActiveSupport::TestCase
  GameData = RodTheBot::EdgeRecap::GameData

  NAMES = {
    19 => "#19 K'Andre Miller", 20 => "#20 Sebastian Aho", 53 => "#53 Jackson Blake", 48 => "#48 Jordan Martinook",
    4 => "#4 Shayne Gostisbehere", 26 => "#26 Sean Walker", 74 => "#74 Jaccob Slavin"
  }.freeze

  SKATERS = [
    GameData::Skater.new(player_id: 19, miles: 3.0844, seconds: 1301),
    GameData::Skater.new(player_id: 20, miles: 2.9409, seconds: 1130),
    GameData::Skater.new(player_id: 53, miles: 2.7701, seconds: 1015),
    GameData::Skater.new(player_id: 48, miles: 2.7554, seconds: 1223)
  ].freeze

  MARKS = [
    GameData::Mark.new(kind: :shot, player_id: 4, mph: 91.98, rank: 6),
    GameData::Mark.new(kind: :shot, player_id: 26, mph: 91.32, rank: 8),
    GameData::Mark.new(kind: :speed, player_id: 74, mph: 22.3693, rank: 10)
  ].freeze

  test "builds the full thread" do
    team, skaters, marks = posts

    assert_equal <<~POST.chomp, team
      ⛸️ EDGE recap: Hurricanes vs. Kraken

      Hurricanes skated 45.28 mi (7th most in their last 10 games)
      Kraken: 44.93 mi

      Even strength 39.58 · Power play 3.48 · Penalty kill 2.22
    POST
    assert_equal <<~POST.chomp, skaters
      ⛸️ Most ice covered:

      #19 K'Andre Miller: 3.08 mi in 21:41
      #20 Sebastian Aho: 2.94 mi in 18:50
      #53 Jackson Blake: 2.77 mi in 16:55
    POST
    assert_equal <<~POST.chomp, marks
      📈 New on the Hurricanes' season top 10:

      💥 #4 Shayne Gostisbehere: 91.98 mph shot (6th hardest)
      💥 #26 Sean Walker: 91.32 mph shot (8th hardest)
      ⚡ #74 Jaccob Slavin: 22.37 mph (10th fastest)
    POST
  end

  test "road game title" do
    assert_equal "⛸️ EDGE recap: Hurricanes at Kraken", posts(home: false).first.lines.first.chomp
  end

  test "rank wording" do
    assert_includes posts(result: result(rank: 1)).first, "45.28 mi (most in their last 10 games)"
    assert_includes posts(result: result(rank: 10)).first, "45.28 mi (fewest in their last 10 games)"
    assert_includes posts(result: result(rank: 3, games: 6)).first, "45.28 mi (3rd most in their last 6 games)"
    assert_includes posts(result: result(rank: 1, games: 2)).first, "Hurricanes skated 45.28 mi\n"
  end

  test "omits the opponent line without opponent data" do
    refute_includes posts(result: result(opponent_distance: nil)).first, "Kraken:"
  end

  test "omits a split with no ice time" do
    assert_equal "Even strength 39.58 · Penalty kill 2.22", posts(result: result(power_play: nil)).first.lines.last
  end

  test "skips skaters without a name and fills from the next" do
    skaters = posts(names: NAMES.except(19))[1]

    assert_equal ["#20 Sebastian Aho: 2.94 mi in 18:50", "#53 Jackson Blake: 2.77 mi in 16:55", "#48 Jordan Martinook: 2.76 mi in 20:23"],
      skaters.lines(chomp: true).last(3)
  end

  test "no skater post without skaters" do
    thread = posts(result: result(skaters: []))

    assert_equal 2, thread.size
    assert thread.last.start_with?("📈")
  end

  test "no season-marks post without marks" do
    assert_equal 2, posts(result: result(marks: [])).size
  end

  test "skips a mark whose player has no name" do
    assert_equal 2, posts(names: NAMES.except(26)).last.lines.grep(/mph/).size
  end

  test "top of list reads without an ordinal" do
    marks = [GameData::Mark.new(kind: :shot, player_id: 4, mph: 99.0, rank: 1), GameData::Mark.new(kind: :speed, player_id: 74, mph: 23.9, rank: 1)]
    post = posts(result: result(marks: marks)).last

    assert_includes post, "99.00 mph shot (hardest)"
    assert_includes post, "23.90 mph (fastest)"
  end

  test "season marks drop trailing lines to fit the limit" do
    post = posts(limit: 120).last

    assert_operator post.length, :<=, 120
    assert post.start_with?("📈 New on the Hurricanes' season top 10:\n\n💥 #4 Shayne Gostisbehere")
    refute_includes post, "Slavin"
  end

  private

  def result(**overrides)
    GameData::Result.new(**{
      distance: 45.2762, even: 39.58, power_play: 3.4776, penalty_kill: 2.2186, rank: 7, games: 10,
      opponent_distance: 44.9257, skaters: SKATERS, marks: MARKS
    }.merge(overrides))
  end

  def posts(result: self.result, names: NAMES, home: true, limit: 280)
    RodTheBot::EdgeRecap::Formatter.new(
      result: result, names: names.method(:[]), team_name: "Hurricanes", opponent_name: "Kraken", home: home, limit: limit
    ).posts
  end
end
