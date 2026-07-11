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
    plays = [1, 2, 3].map { |id| {"eventId" => id, "details" => {"goalieInNetId" => 52}} }

    result = detect(goalie_id: 52, plays: plays)

    assert_equal :stale_cache, result.status
    assert_equal "52", @redis.get(state_key)
  end

  private

  def detect(goalie_id:, plays: [])
    @detector.detect(game_id: 10, team_id: 12, goalie_id: goalie_id, event_id: 20, plays: plays)
  end

  def state_key = "game:10:current_goalie:12"
end
