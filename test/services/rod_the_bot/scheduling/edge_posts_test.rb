require "test_helper"

class RodTheBot::Scheduling::EdgePostsTest < ActiveSupport::TestCase
  setup { Sidekiq::Worker.clear_all }

  test "spaces every EDGE worker inside the available pregame window" do
    now = Time.zone.parse("2026-01-01 12:00")

    RodTheBot::Scheduling::EdgePosts.new.schedule(game_id: 10, game_time: now + 3.hours, now: now)

    assert RodTheBot::Scheduling::EdgePosts::WORKERS.all? { |worker| worker.jobs.one? }
  end

  test "skips EDGE posts when the game is too close" do
    now = Time.zone.parse("2026-01-01 12:00")

    RodTheBot::Scheduling::EdgePosts.new.schedule(game_id: 10, game_time: now + 30.minutes, now: now)

    assert RodTheBot::Scheduling::EdgePosts::WORKERS.all? { |worker| worker.jobs.empty? }
  end
end
