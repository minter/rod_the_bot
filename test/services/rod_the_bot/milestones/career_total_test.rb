require "test_helper"

class RodTheBot::Milestones::CareerTotalTest < ActiveSupport::TestCase
  test "combines pregame totals with goals and assists from the recorded game feed shape" do
    redis = MockRedis.new
    redis.set("pregame:10:player:42:points", 99)
    feed = -> { {"plays" => [
      {"typeDescKey" => "goal", "details" => {"scoringPlayerId" => 42}},
      {"typeDescKey" => "goal", "details" => {"assist1PlayerId" => 42}}
    ]} }

    total = RodTheBot::Milestones::CareerTotal.new(game_id: 10, feed: feed, redis: redis)

    assert_equal 101, total.for(42, "points")
  end

  test "falls back to career stats when pregame data is absent" do
    stats = ->(_player_id) { {"goals" => 50} }
    total = RodTheBot::Milestones::CareerTotal.new(game_id: 10, feed: -> { {} }, redis: MockRedis.new, career_stats: stats)

    assert_equal 50, total.for(42, "goals")
  end
end
