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

      RodTheBot::Post.expects(:perform_async).once

      @worker.perform(@game_id, @play_id, modified_original_play)
    end
  end

  def test_perform_without_scoring_change
    VCR.use_cassette("nhl_game_#{@game_id}_no_scoring_change", record: :new_episodes) do
      # Use the actual play data from the API
      feed = NhlApi.fetch_pbp_feed(@game_id)
      actual_play = feed["plays"].find { |play| play["eventId"].to_s == @play_id }

      RodTheBot::Post.expects(:perform_async).never

      @worker.perform(@game_id, @play_id, actual_play)
    end
  end

  def test_perform_with_non_goal_play
    VCR.use_cassette("nhl_game_#{@game_id}_non_goal_play", record: :new_episodes) do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      non_goal_play = feed["plays"].find { |play| play["typeDescKey"] != "goal" }

      RodTheBot::Post.expects(:perform_async).never

      @worker.perform(@game_id, non_goal_play["eventId"].to_s, @original_play)
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
end
