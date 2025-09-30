require "test_helper"

class RodTheBot::ScoringChangeWorkerTest < ActiveSupport::TestCase
  def setup
    @worker = RodTheBot::ScoringChangeWorker.new
    @game_id = "2024010043"
    @play_id = "157"
    @original_play = {
      "details" => {
        "scoringPlayerId" => "8480830",
        "assist1PlayerId" => "8478427",
        "assist2PlayerId" => nil
      }
    }
    @redis_key = "game:#{@game_id}:goal:#{@play_id}"
    # Update to match the new format in the worker
    @scoring_key_pattern = /^#{Regexp.escape(@redis_key)}:scoring:\d+$/
  end

  def test_perform_with_scoring_change
    VCR.use_cassette("nhl_game_#{@game_id}_scoring_change", record: :new_episodes) do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      actual_goal_play = feed["plays"].find { |play| play["typeDescKey"] == "goal" }

      return skip("No goal play found in the feed") unless actual_goal_play

      @play_id = actual_goal_play["eventId"].to_s

      # Modify the original play to ensure a change is detected
      modified_original_play = actual_goal_play.deep_dup
      modified_original_play["details"]["assist1PlayerId"] = "8000000"  # Use a non-existent player ID

      # Allow any parameters for Post.perform_async
      RodTheBot::Post.expects(:perform_async).once

      @worker.perform(@game_id, @play_id, modified_original_play, @redis_key)
    end
  end

  def test_perform_without_scoring_change
    VCR.use_cassette("nhl_game_#{@game_id}_no_scoring_change", record: :new_episodes) do
      # Use the actual play data from the API
      feed = NhlApi.fetch_pbp_feed(@game_id)
      # Find any actual goal play in the feed
      actual_play = feed["plays"].find { |play| play["typeDescKey"] == "goal" }

      return skip("No goal play found in the feed") unless actual_play

      # Use the actual play ID that exists
      actual_play_id = actual_play["eventId"].to_s

      RodTheBot::Post.expects(:perform_async).never

      @worker.perform(@game_id, actual_play_id, actual_play, @redis_key)
    end
  end

  def test_perform_with_non_goal_play
    VCR.use_cassette("nhl_game_#{@game_id}_non_goal_play", record: :new_episodes) do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      non_goal_play = feed["plays"].find { |play| play["typeDescKey"] != "goal" }

      RodTheBot::Post.expects(:perform_async).never

      @worker.perform(@game_id, non_goal_play["eventId"].to_s, @original_play, @redis_key)
    end
  end

  def test_build_players
    VCR.use_cassette("nhl_game_#{@game_id}_build_players", record: :new_episodes) do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      players = @worker.build_players(feed)

      assert_kind_of Hash, players
      assert_includes players.keys, "8480830"
      assert_equal "Andrei Svechnikov", players["8480830"][:name]
      assert_equal "37", players["8480830"][:number].to_s
    end
  end

  def test_format_post
    VCR.use_cassette("nhl_game_#{@game_id}_format_post", record: :new_episodes) do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      play = feed["plays"].find { |p| p["typeDescKey"] == "goal" }
      @worker.instance_variable_set(:@feed, feed)
      @worker.instance_variable_set(:@play, play)

      scoring_team = feed["homeTeam"]
      period_name = "1st Period"
      players = @worker.build_players(feed)

      post = @worker.format_post(scoring_team, period_name, players)

      assert_match(/🔔 Scoring Change/, post)
      assert_match(/The Hurricanes goal at \d+:\d+ of the 1st Period now reads:/, post)
      assert_match(/🚨 .+ \(\d+\)/, post)
      assert_match(/🍎 .+ \(\d+\)/, post)
      assert_match(/🍎🍎 .+ \(\d+\)/, post)
    end
  end

  def test_overturned_goal_with_challenge
    # Test the Carolina goal that was overturned in game 2025010061
    overturned_game_id = "2025010061"
    overturned_play_id = "687" # Fictional event ID for the overturned goal

    # Create mock original play data for Bradly Nadeau goal
    original_play = {
      "eventId" => 687,
      "timeInPeriod" => "12:17",
      "periodDescriptor" => {"number" => 2},
      "typeDescKey" => "goal",
      "details" => {
        "scoringPlayerId" => 8484203,     # Bradly Nadeau
        "eventOwnerTeamId" => 12,         # Carolina
        "assist1PlayerId" => nil,
        "assist2PlayerId" => nil
      }
    }

    redis_key = "game:#{overturned_game_id}:goal:#{overturned_play_id}"

    VCR.use_cassette("nhl_game_#{overturned_game_id}_overturned_goal", record: :new_episodes) do
      # Mock the Post.perform_async call to verify it gets called with overturn message
      RodTheBot::Post.expects(:perform_async).once.with do |post, scoring_key, parent_key, _third_param, _fourth_param|
        # Verify the post content
        assert_match(/❌ Goal Overturned/, post)
        assert_match(/Carolina goal by Bradly Nadeau/, post)
        assert_match(/12:17 of the 2nd Period/, post)
        assert_match(/offside challenge by Florida/, post)

        # Verify the key structure
        assert_match(/#{Regexp.escape(redis_key)}:overturn:\d+/, scoring_key)
        assert_equal redis_key, parent_key

        true
      end

      @worker.perform(overturned_game_id, overturned_play_id, original_play, redis_key)
    end
  end

  def test_no_challenge_found_for_missing_goal
    # Test when a goal is missing but there's no challenge event nearby
    overturned_game_id = "2025010061"
    fake_play_id = "999999" # Non-existent play ID

    original_play = {
      "eventId" => 999999,
      "timeInPeriod" => "05:30",  # Time with no challenge events nearby
      "periodDescriptor" => {"number" => 1},
      "typeDescKey" => "goal",
      "details" => {
        "scoringPlayerId" => 8484203,
        "eventOwnerTeamId" => 12
      }
    }

    redis_key = "game:#{overturned_game_id}:goal:#{fake_play_id}"

    VCR.use_cassette("nhl_game_#{overturned_game_id}_no_challenge", record: :new_episodes) do
      # Should not post anything when no challenge is found
      RodTheBot::Post.expects(:perform_async).never

      @worker.perform(overturned_game_id, fake_play_id, original_play, redis_key)
    end
  end
end
