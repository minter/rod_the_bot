require "test_helper"
require "vcr"
require "sidekiq/testing"

class RodTheBot::GoalieChangeWorkerTest < ActiveSupport::TestCase
  def setup
    @worker = RodTheBot::GoalieChangeWorker.new
    ENV["NHL_TEAM_ID"] = "12"  # Carolina Hurricanes (for consistency with other tests)
    Sidekiq::Testing.fake!  # Enable fake Sidekiq queue
  end

  def teardown
    Sidekiq::Worker.clear_all  # Clear Sidekiq queue after each test
    REDIS.flushall  # Clear Redis after each test
  end

  test "detects actual goalie change in game 2025010061 from Bobrovsky to Cooper Black" do
    game_id = "2025010061"
    
    VCR.use_cassette("nhl_game_#{game_id}_gamecenter_pbp", allow_playback_repeats: true) do
      # Get the actual game feed to extract real data
      feed = NhlApi.fetch_pbp_feed(game_id)
      
      # Set up initial state - Bobrovsky (8475683) was starting goalie for Florida (team 13)
      REDIS.set("game:#{game_id}:current_goalie:13", "8475683", ex: 28800)
      
      # Find the actual shot event that revealed the goalie change (event 809)
      goalie_change_play = feed["plays"].find { |play| play["eventId"] == 809 }
      assert_not_nil goalie_change_play, "Could not find event 809 in game feed"
      assert_equal "shot-on-goal", goalie_change_play["typeDescKey"]
      assert_equal 8484900, goalie_change_play["details"]["goalieInNetId"] # Cooper Black

      VCR.use_cassette("nhl_api/player_8484900_landing", allow_playback_repeats: true) do
        assert_difference -> { RodTheBot::Post.jobs.size }, 1 do
          @worker.perform(game_id, goalie_change_play)
        end

        # Verify the exact post content
        post_content = RodTheBot::Post.jobs.last["args"].first
        assert_match(/🥅 Goaltending change for Florida!/, post_content)
        assert_match(/Now in goal for the Panthers, #31 Cooper Black/, post_content)

        # Verify headshot image is included
        post_images = RodTheBot::Post.jobs.last["args"][4]
        assert_not_nil post_images
        assert post_images.is_a?(Array)
        assert_match(/8484900\.png/, post_images.first) if post_images.any?

        # Verify Redis cache was updated with new goalie
        assert_equal "8484900", REDIS.get("game:#{game_id}:current_goalie:13")
      end
    end
  end

  test "does not post when goalie has not changed" do
    game_id = "2025010061"
    
    VCR.use_cassette("nhl_game_#{game_id}_gamecenter_pbp", allow_playback_repeats: true) do
      feed = NhlApi.fetch_pbp_feed(game_id)
      
      # Set up cache with Cooper Black already active
      REDIS.set("game:#{game_id}:current_goalie:13", "8484900", ex: 28800)
      
      # Use a later shot event where Cooper Black is still in goal
      later_shot_play = feed["plays"].find { |play| 
        play["eventId"] > 809 && 
        play["typeDescKey"] == "shot-on-goal" && 
        play["details"] && 
        play["details"]["goalieInNetId"] == 8484900 
      }
      
      skip "No later shot events found for Cooper Black" unless later_shot_play

      assert_no_difference -> { RodTheBot::Post.jobs.size } do
        @worker.perform(game_id, later_shot_play)
      end

      # Verify cache unchanged
      assert_equal "8484900", REDIS.get("game:#{game_id}:current_goalie:13")
    end
  end

  test "does not process play without goalieInNetId" do
    game_id = "2025010061"
    
    VCR.use_cassette("nhl_game_#{game_id}_gamecenter_pbp", allow_playback_repeats: true) do
      feed = NhlApi.fetch_pbp_feed(game_id)
      
      # Find a hit or other event without goalie info
      non_shot_play = feed["plays"].find { |play| 
        play["typeDescKey"] == "hit" && 
        (!play["details"] || !play["details"]["goalieInNetId"])
      }
      
      skip "No non-shot events found" unless non_shot_play

      assert_no_difference -> { RodTheBot::Post.jobs.size } do
        @worker.perform(game_id, non_shot_play)
      end
    end
  end

  test "handles missing player in roster gracefully" do
    game_id = "2025010061"
    
    # Create fake shot event with non-existent goalie ID
    fake_play = {
      "eventId" => 999,
      "typeDescKey" => "shot-on-goal",
      "details" => {
        "goalieInNetId" => 9999999,  # Non-existent goalie
        "eventOwnerTeamId" => 12
      }
    }

    # Set up cache with different goalie to trigger change detection
    REDIS.set("game:#{game_id}:current_goalie:13", "8475683", ex: 28800)

    VCR.use_cassette("nhl_game_#{game_id}_gamecenter_pbp", allow_playback_repeats: true) do
      assert_no_difference -> { RodTheBot::Post.jobs.size } do
        @worker.perform(game_id, fake_play)
      end

      # Verify cache was not updated
      assert_equal "8475683", REDIS.get("game:#{game_id}:current_goalie:13")
    end
  end
end
