require "test_helper"

class RodTheBot::GoalieChange::DetectorTest < ActiveSupport::TestCase
  setup do
    @redis = MockRedis.new
    @detector = RodTheBot::GoalieChange::Detector.new(redis: @redis)
  end

  test "initializes missing state without reporting a change" do
    result = detect(goalie_id: 31)

    assert_equal :initialized, result.status
    assert_equal "31", @redis.get(state_key)
  end

  test "claims a real change and commits it separately" do
    @redis.set(state_key, "31")
    result = detect(goalie_id: 52)

    assert_equal :changed, result.status
    assert_equal "31", @redis.get(state_key)
    @detector.commit(game_id: 10, team_id: 12, goalie_id: 52)
    assert_equal "52", @redis.get(state_key)
  end

  test "updates stale state when the goalie already appeared repeatedly" do
    @redis.set(state_key, "31")
    plays = [1, 2, 3].map { |order| play(order, 52) }

    result = detect(goalie_id: 52, plays: plays)

    assert_equal :stale_cache, result.status
    assert_equal "52", @redis.get(state_key)
  end

  test "orders prior appearances by sortOrder rather than eventId" do
    @redis.set(state_key, "31")
    plays = [play(5, 52, event_id: 900), play(6, 52, event_id: 901), play(7, 52, event_id: 902)]

    result = detect(goalie_id: 52, plays: plays, sort_order: 8)

    assert_equal :stale_cache, result.status
  end

  test "ignores appearances later in the feed than the triggering play" do
    @redis.set(state_key, "31")
    plays = [play(20, 52), play(25, 52), play(30, 52), play(35, 52)]

    result = detect(goalie_id: 52, plays: plays, sort_order: 20)

    assert_equal :changed, result.status
    assert_equal "31", @redis.get(state_key)
  end

  test "reports a change when a goal and missed shots precede the first shot on goal" do
    @redis.set(state_key, "31")
    plays = [play(428, 52, type: "goal"), play(440, 52, type: "missed-shot"), play(445, 52, type: "missed-shot"), play(460, 52)]

    result = detect(goalie_id: 52, plays: plays, sort_order: 428)

    assert_equal :changed, result.status
  end

  private

  def detect(goalie_id:, plays: [], sort_order: 20)
    @detector.detect(game_id: 10, team_id: 12, goalie_id: goalie_id, sort_order: sort_order, plays: plays)
  end

  def play(sort_order, goalie_id, event_id: sort_order, type: "shot-on-goal")
    {"eventId" => event_id, "sortOrder" => sort_order, "typeDescKey" => type, "details" => {"goalieInNetId" => goalie_id}}
  end

  def state_key = "game:10:current_goalie:12"
end
