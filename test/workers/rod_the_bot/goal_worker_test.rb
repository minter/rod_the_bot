require "test_helper"

class RodTheBot::GoalWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @goal_worker = RodTheBot::GoalWorker.new
    ENV["NHL_TEAM_ID"] = "12"
  end

  def test_away_goal
    @game_id = "2023020702"
    @play_id = "157"
    VCR.use_cassette("nhl_game_#{@game_id}_goal_play_#{@play_id}", allow_playback_repeats: true) do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      play = feed["plays"].find { |play| play["eventId"].to_i == @play_id.to_i }

      @goal_worker.perform(@game_id, play)

      assert_equal 1, RodTheBot::Post.jobs.size
      assert_equal 1, RodTheBot::ScoringChangeWorker.jobs.size
      expected_output = <<~POST
        👎 Red Wings Goal
        
        🚨 Klim Kostin (3)
        🍎 Joe Veleno (10)
        🍎🍎 Daniel Sprong (18)
        ⏱️  02:27 1st Period
        
        DET 1 - CAR 0
      POST
      assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
    end
  end

  def test_home_goal
    @game_id = "2023020702"
    @play_id = "159"
    VCR.use_cassette("nhl_game_#{@game_id}_goal_play_#{@play_id}", allow_playback_repeats: true) do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      play = feed["plays"].find { |play| play["eventId"].to_i == @play_id.to_i }

      @goal_worker.perform(@game_id, play)

      assert_equal 1, RodTheBot::Post.jobs.size
      assert_equal 1, RodTheBot::ScoringChangeWorker.jobs.size
      expected_output = <<~POST
        🎉 Hurricanes GOOOOOOOAL!
        
        🚨 Jordan Martinook (6)
        🍎 Brent Burns (18)
        🍎🍎 Jordan Staal (9)
        ⏱️  03:14 1st Period
        
        DET 1 - CAR 1
      POST
      assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
    end
  end

  def test_away_ppg
    @game_id = "2023020702"
    @play_id = "390"
    VCR.use_cassette("nhl_game_#{@game_id}_goal_play_#{@play_id}", allow_playback_repeats: true) do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      play = feed["plays"].find { |play| play["eventId"].to_i == @play_id.to_i }

      @goal_worker.perform(@game_id, play)

      assert_equal 1, RodTheBot::Post.jobs.size
      assert_equal 1, RodTheBot::ScoringChangeWorker.jobs.size
      expected_output = <<~POST
        👎 Red Wings Power Play Goal
        
        🚨 J.T. Compher (10)
        🍎 Dylan Larkin (22)
        🍎🍎 Shayne Gostisbehere (24)
        ⏱️  19:17 2nd Period
        
        DET 2 - CAR 2
      POST
      assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
    end
  end

  def test_home_shg
    @game_id = "2023020360"
    @play_id = "739"
    VCR.use_cassette("nhl_game_#{@game_id}_goal_play_#{@play_id}", allow_playback_repeats: true) do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      play = feed["plays"].find { |play| play["eventId"].to_i == @play_id.to_i }

      @goal_worker.perform(@game_id, play)

      assert_equal 1, RodTheBot::Post.jobs.size
      assert_equal 1, RodTheBot::ScoringChangeWorker.jobs.size
      expected_output = <<~POST
        🎉 Hurricanes Shorthanded GOOOOOOOAL!
        
        🚨 Brady Skjei (4)
        🍎 Teuvo Teravainen (7)
        ⏱️  08:05 3rd Period
        
        BUF 1 - CAR 6
      POST
      assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
    end
  end

  def test_home_eng
    @game_id = "2023020702"
    @play_id = "859"
    VCR.use_cassette("nhl_game_#{@game_id}_goal_play_#{@play_id}", allow_playback_repeats: true) do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      play = feed["plays"].find { |play| play["eventId"].to_i == @play_id.to_i }

      @goal_worker.perform(@game_id, play)

      assert_equal 1, RodTheBot::Post.jobs.size
      assert_equal 1, RodTheBot::ScoringChangeWorker.jobs.size
      expected_output = <<~POST
        🎉 Hurricanes Empty Net GOOOOOOOAL!
        
        🚨 Sebastian Aho (16)
        🍎 Martin Necas (18)
        🍎🍎 Andrei Svechnikov (19)
        ⏱️  18:44 3rd Period
        
        DET 2 - CAR 4
      POST
      assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
    end
  end

  def test_home_ppg_eng
    @game_id = "2023020542"
    @play_id = "92"
    VCR.use_cassette("nhl_game_#{@game_id}_goal_play_#{@play_id}", allow_playback_repeats: true) do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      play = feed["plays"].find { |play| play["eventId"].to_i == @play_id.to_i }

      @goal_worker.perform(@game_id, play)

      assert_equal 1, RodTheBot::Post.jobs.size
      assert_equal 1, RodTheBot::ScoringChangeWorker.jobs.size
      expected_output = <<~POST
        🎉 Hurricanes Power Play, Empty Net GOOOOOOOAL!
        
        🚨 Andrei Svechnikov (6)
        🍎 Sebastian Aho (25)
        🍎🍎 Brent Burns (13)
        ⏱️  19:41 3rd Period
        
        MTL 3 - CAR 5
      POST
      assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
    end
  end
end
