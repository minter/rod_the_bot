require "test_helper"

class RodTheBot::MilestoneCheckerWorkerTest < ActiveSupport::TestCase
  def setup
    # Clear Sidekiq jobs at the start to ensure test isolation
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::MilestoneCheckerWorker.new
    @game_id = "2025020070"
    ENV["NHL_TEAM_ID"] = "12"
    ENV["TEAM_HASHTAGS"] = "#Canes"
  end

  def teardown
    Sidekiq::Worker.clear_all
    # Clean up Redis pre-game stats keys
    REDIS.keys("pregame:*").each { |key| REDIS.del(key) }
  end

  test "check_goal_milestone detects 100th goal" do
    VCR.use_cassette("milestone_checker_seth_jarvis_100th_goal") do
      play = {
        "typeDescKey" => "goal",
        "eventId" => 391,
        "details" => {
          "scoringPlayerId" => 8482093,  # Seth Jarvis
          "assist1PlayerId" => 8476906,
          "assist2PlayerId" => nil
        }
      }

      # Mock pre-game stats in Redis (Jarvis had 99 goals before this game)
      REDIS.set("pregame:#{@game_id}:player:8482093:goals", 99)
      REDIS.set("pregame:#{@game_id}:player:8482093:points", 216)
      REDIS.set("pregame:#{@game_id}:player:8482093:assists", 117)

      # Mock pre-game stats for assist player (not a milestone)
      REDIS.set("pregame:#{@game_id}:player:8476906:goals", 10)
      REDIS.set("pregame:#{@game_id}:player:8476906:points", 50)
      REDIS.set("pregame:#{@game_id}:player:8476906:assists", 40)

      # Mock the game feed to show Jarvis scored once in this game
      feed = {
        "plays" => [
          {
            "typeDescKey" => "goal",
            "eventId" => 391,
            "details" => {
              "scoringPlayerId" => 8482093,
              "assist1PlayerId" => 8476906
            }
          }
        ]
      }

      NhlApi.stubs(:fetch_pbp_feed).returns(feed)

      # Mock roster data
      NhlApi.stubs(:game_rosters).returns({
        8482093 => {number: 24, name: "Seth Jarvis", team_id: 12},
        8476906 => {number: 65, name: "William Carrier", team_id: 12}
      })

      @worker.perform(@game_id, play)

      # Should have scheduled a post for the milestone (99 + 1 = 100)
      assert_equal 1, RodTheBot::Post.jobs.size
      job = RodTheBot::Post.jobs.first
      assert_match(/MILESTONE/, job["args"][0])
      assert_match(/100 career goals/, job["args"][0])
      assert_match(/Seth Jarvis/, job["args"][0])
    end
  end

  test "check_goal_milestone skips non-milestone goals" do
    VCR.use_cassette("milestone_checker_non_milestone") do
      play = {
        "typeDescKey" => "goal",
        "eventId" => 391,
        "details" => {
          "scoringPlayerId" => 8482093,
          "assist1PlayerId" => nil,
          "assist2PlayerId" => nil
        }
      }

      # Mock pre-game stats in Redis (Jarvis had 98 goals before this game)
      REDIS.set("pregame:#{@game_id}:player:8482093:goals", 98)
      REDIS.set("pregame:#{@game_id}:player:8482093:points", 215)
      REDIS.set("pregame:#{@game_id}:player:8482093:assists", 117)

      # Mock the game feed to show Jarvis scored once in this game (98 + 1 = 99, not a milestone)
      feed = {
        "plays" => [
          {
            "typeDescKey" => "goal",
            "eventId" => 391,
            "details" => {
              "scoringPlayerId" => 8482093,
              "assist1PlayerId" => nil
            }
          }
        ]
      }

      NhlApi.stubs(:fetch_pbp_feed).returns(feed)

      # Mock roster data
      NhlApi.stubs(:game_rosters).returns({
        8482093 => {number: 24, name: "Seth Jarvis", team_id: 12}
      })

      @worker.perform(@game_id, play)

      # Should not have scheduled any posts (99 is not a milestone)
      assert_equal 0, RodTheBot::Post.jobs.size
    end
  end

  test "check_assist_milestone detects 100th assist" do
    VCR.use_cassette("milestone_checker_assist") do
      play = {
        "typeDescKey" => "goal",
        "eventId" => 391,
        "details" => {
          "scoringPlayerId" => 8476906,
          "assist1PlayerId" => 8482093,  # Seth Jarvis gets assist
          "assist2PlayerId" => nil
        }
      }

      # Mock pre-game stats for Jarvis (had 99 assists before this game)
      REDIS.set("pregame:#{@game_id}:player:8482093:goals", 99)
      REDIS.set("pregame:#{@game_id}:player:8482093:points", 217)
      REDIS.set("pregame:#{@game_id}:player:8482093:assists", 99)

      # Mock pre-game stats for scorer (not near any milestone)
      REDIS.set("pregame:#{@game_id}:player:8476906:goals", 50)
      REDIS.set("pregame:#{@game_id}:player:8476906:points", 150)
      REDIS.set("pregame:#{@game_id}:player:8476906:assists", 100)

      # Mock the game feed showing this goal with Jarvis getting an assist
      feed = {
        "plays" => [
          {
            "typeDescKey" => "goal",
            "eventId" => 391,
            "details" => {
              "scoringPlayerId" => 8476906,
              "assist1PlayerId" => 8482093
            }
          }
        ]
      }

      NhlApi.stubs(:fetch_pbp_feed).returns(feed)

      # Mock roster data
      NhlApi.stubs(:game_rosters).returns({
        8476906 => {number: 65, name: "William Carrier", team_id: 12},
        8482093 => {number: 24, name: "Seth Jarvis", team_id: 12}
      })

      @worker.perform(@game_id, play)

      # Should have scheduled a post for the assist milestone (99 + 1 = 100)
      assert_operator RodTheBot::Post.jobs.size, :>=, 1

      # Find the assist milestone post
      assist_post = RodTheBot::Post.jobs.find do |job|
        job["args"][0].include?("100 career assists")
      end

      assert_not_nil assist_post, "Should have scheduled an assist milestone post"
      assert_match(/Seth Jarvis/, assist_post["args"][0])
    end
  end
end
