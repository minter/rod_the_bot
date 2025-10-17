require "test_helper"

class RodTheBot::MilestoneCheckerWorkerTest < ActiveSupport::TestCase
  def setup
    @worker = RodTheBot::MilestoneCheckerWorker.new
    @game_id = "2025020070"
    ENV["NHL_TEAM_ID"] = "12"
    ENV["TEAM_HASHTAGS"] = "#Canes"
  end

  def teardown
    Sidekiq::Worker.clear_all
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

      # Mock the career stats API to return 100 goals for scorer
      jarvis_stats = {
        "data" => [{
          "goals" => 100,
          "points" => 217,
          "assists" => 117
        }]
      }

      # Mock stats for assist player (not a milestone)
      carrier_stats = {
        "data" => [{
          "goals" => 10,
          "points" => 50,
          "assists" => 40
        }]
      }

      HTTParty.stubs(:get)
        .with(regexp_matches(/playerId=8482093/))
        .returns(stub(success?: true, parsed_response: jarvis_stats))

      HTTParty.stubs(:get)
        .with(regexp_matches(/playerId=8476906/))
        .returns(stub(success?: true, parsed_response: carrier_stats))

      # Mock roster data
      NhlApi.stubs(:game_rosters).returns({
        8482093 => { number: 24, name: "Seth Jarvis", team_id: 12 },
        8476906 => { number: 65, name: "William Carrier", team_id: 12 }
      })

      @worker.perform(@game_id, play)

      # Should have scheduled a post for the milestone
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

      # Mock the career stats API to return 99 goals (not a milestone)
      career_stats_response = {
        "data" => [{
          "goals" => 99,
          "points" => 216,
          "assists" => 117
        }]
      }

      HTTParty.stubs(:get)
        .with(regexp_matches(/playerId=8482093/))
        .returns(stub(success?: true, parsed_response: career_stats_response))

      # Mock roster data
      NhlApi.stubs(:game_rosters).returns({
        8482093 => { number: 24, name: "Seth Jarvis", team_id: 12 }
      })

      @worker.perform(@game_id, play)

      # Should not have scheduled any posts
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

      # Mock the career stats API
      scorer_stats = {
        "data" => [{
          "goals" => 50,
          "points" => 150,
          "assists" => 100
        }]
      }

      assist_stats = {
        "data" => [{
          "goals" => 99,
          "points" => 217,
          "assists" => 100  # Milestone!
        }]
      }

      HTTParty.stubs(:get)
        .with(regexp_matches(/playerId=8476906/))
        .returns(stub(success?: true, parsed_response: scorer_stats))

      HTTParty.stubs(:get)
        .with(regexp_matches(/playerId=8482093/))
        .returns(stub(success?: true, parsed_response: assist_stats))

      # Mock roster data
      NhlApi.stubs(:game_rosters).returns({
        8476906 => { number: 65, name: "William Carrier", team_id: 12 },
        8482093 => { number: 24, name: "Seth Jarvis", team_id: 12 }
      })

      @worker.perform(@game_id, play)

      # Should have scheduled a post for the assist milestone
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

