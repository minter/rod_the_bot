require "test_helper"

class RodTheBot::PostThreadTest < ActiveSupport::TestCase
  setup do
    Sidekiq::Worker.clear_all
  end

  test "split accounts for hashtags and preserves all words" do
    ENV["TEAM_HASHTAGS"] = "#canes"
    text = (["word"] * 100).join(" ")

    chunks = RodTheBot::PostThread.split(text)

    assert chunks.all? { |chunk| chunk.length <= 293 }
    assert_equal text.split, chunks.flat_map(&:split)
  ensure
    ENV.delete("TEAM_HASHTAGS")
  end

  test "enqueue creates a delayed reply chain" do
    chunks = ["one", "two", "three"]

    RodTheBot::PostThread.enqueue(chunks, key: "thread", delay: 10.seconds)

    assert_equal ["one", "thread:1"], RodTheBot::Post.jobs.first["args"]
    assert_equal ["two", "thread:2", "thread:1"], RodTheBot::Post.jobs.second["args"]
    assert_equal ["three", "thread:3", "thread:2"], RodTheBot::Post.jobs.third["args"]
  end
end
