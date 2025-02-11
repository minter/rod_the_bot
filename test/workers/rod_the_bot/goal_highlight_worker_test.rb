require "test_helper"

class RodTheBot::GoalHighlightWorkerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @game_id = "2024010043"
    @base_redis_key = "game:#{@game_id}:goal:157"
    @redis_key = "#{@base_redis_key}:#{Time.now.strftime("%Y%m%d")}"
    VCR.use_cassette("nhl_api_#{@game_id}") do
      @pbp_feed = NhlApi.fetch_pbp_feed(@game_id)
      @landing_feed = NhlApi.fetch_landing_feed(@game_id)
    end
    @goal_play = @pbp_feed["plays"].find { |play| play["typeDescKey"] == "goal" }
    @play_id = @goal_play["eventId"]
    Sidekiq::Worker.clear_all
  end

  teardown do
    VCR.eject_cassette
  end

  test "performs goal highlight post when highlight is available" do
    VCR.use_cassette("nhl_api_#{@game_id}_goal_highlight") do
      RodTheBot::Post.expects(:perform_async).once.with(
        anything,
        @redis_key,
        nil,
        nil,
        [],
        "spec/fixtures/test_video.mp4"
      )

      assert_no_enqueued_jobs(only: RodTheBot::GoalHighlightWorker) do
        RodTheBot::GoalHighlightWorker.new.perform(@game_id, @play_id, @base_redis_key)
      end
    end
  end

  test "reschedules worker when highlight is not available" do
    VCR.use_cassette("nhl_api_#{@game_id}_no_highlight") do
      # Fetch the original data
      pbp_feed = NhlApi.fetch_pbp_feed(@game_id)
      landing_feed = NhlApi.fetch_landing_feed(@game_id)
      play_data = NhlApi.fetch_play(@game_id, @play_id)

      # Find the corresponding landing play and remove the highlight URL
      landing_feed["summary"]["scoring"].each do |period|
        period["goals"].each do |goal|
          goal["highlightClipSharingUrl"] = nil
        end
      end

      # Mock the API calls to return our modified data
      NhlApi.expects(:fetch_pbp_feed).returns(pbp_feed)
      NhlApi.expects(:fetch_landing_feed).returns(landing_feed)
      NhlApi.expects(:fetch_play).with(@game_id, @play_id).returns(play_data)

      # Run the worker
      worker = RodTheBot::GoalHighlightWorker.new

      assert_difference -> { RodTheBot::GoalHighlightWorker.jobs.size }, 1 do
        worker.perform(@game_id, @play_id, @base_redis_key)
      end

      job = RodTheBot::GoalHighlightWorker.jobs.last
      assert_equal [@game_id, @play_id, @base_redis_key], job["args"][0..2]
      assert_in_delta Time.now.to_i, job["args"][3], 1
      assert_in_delta 3.minutes.from_now.to_i, job["at"], 1
    end
  end

  test "does not post or reschedule for non-goal plays" do
    VCR.use_cassette("nhl_api_#{@game_id}_non_goal") do
      non_goal_play = @pbp_feed["plays"].find { |play| play["typeDescKey"] != "goal" }
      non_goal_play_id = non_goal_play["eventId"]

      RodTheBot::Post.expects(:perform_async).never

      assert_no_difference -> { RodTheBot::GoalHighlightWorker.jobs.size } do
        RodTheBot::GoalHighlightWorker.new.perform(@game_id, non_goal_play_id, @base_redis_key)
      end
    end
  end

  test "formats post correctly" do
    VCR.use_cassette("nhl_api_#{@game_id}_format_post") do
      landing_play = @landing_feed["summary"]["scoring"].flat_map { |period| period["goals"] }.find { |goal| goal["timeInPeriod"] == @goal_play["timeInPeriod"] }

      worker = RodTheBot::GoalHighlightWorker.new
      worker.instance_variable_set(:@pbp_feed, @pbp_feed)
      worker.instance_variable_set(:@landing_feed, @landing_feed)
      worker.instance_variable_set(:@pbp_play, @goal_play)
      worker.instance_variable_set(:@landing_play, landing_play)

      expected_post = "🎥 Goal highlight: #{landing_play["firstName"]["default"]} #{landing_play["lastName"]["default"]} (#{landing_play["teamAbbrev"]["default"]}) scores on a #{landing_play["shotType"]} shot at #{landing_play["timeInPeriod"]} of the #{worker.send(:format_period_name, @goal_play["periodDescriptor"]["number"])}."

      if landing_play["assists"].any?
        assists = landing_play["assists"].map { |a| "#{a["firstName"]["default"]} #{a["lastName"]["default"]}" }.join(", ")
        expected_post += " Assisted by #{assists}."
      end

      expected_post += " Score: #{@landing_feed["awayTeam"]["abbrev"]} #{landing_play["awayScore"]} - #{@landing_feed["homeTeam"]["abbrev"]} #{landing_play["homeScore"]}"

      RodTheBot::Post.expects(:perform_async).with(
        expected_post,
        @redis_key,
        nil,
        nil,
        [],
        "spec/fixtures/test_video.mp4"
      )

      worker.perform(@game_id, @play_id, @base_redis_key)
    end
  end

  test "stops retrying after 6 hours" do
    initial_run_time = 7.hours.ago.to_i

    RodTheBot::Post.expects(:perform_async).never

    assert_no_difference -> { RodTheBot::GoalHighlightWorker.jobs.size } do
      worker = RodTheBot::GoalHighlightWorker.new
      worker.perform(@game_id, @play_id, @base_redis_key, initial_run_time)
    end
  end
end
