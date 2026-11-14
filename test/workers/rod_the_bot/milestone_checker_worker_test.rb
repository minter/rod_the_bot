require "test_helper"

class RodTheBot::MilestoneCheckerWorkerTest < ActiveSupport::TestCase
  def setup
    # Clear Sidekiq jobs at the start to ensure test isolation
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::MilestoneCheckerWorker.new
    @game_id = "2025020070"
    ENV["NHL_TEAM_ID"] = "12"
    ENV["TEAM_HASHTAGS"] = "#Canes"
    Nhl::StatsClient.stubs(:teams).returns(12 => {id: 12, franchiseId: 26})
    Nhl::RecordsClient.stubs(:franchise_skater_totals).returns([])
  end

  test "posts when a goal moves the scorer up the franchise list" do
    stub_franchise_goal(scorer_goals: 322)

    @worker.perform(@game_id, franchise_goal_play)

    assert_equal [
      "📈 #20 Sebastian Aho (323) passes Eric Staal for sole possession of 2nd on the franchise's all-time goals list. Next up: Ron Francis (382)."
    ], RodTheBot::Post.jobs.map { |job| job["args"].first }
  end

  test "posts nothing when the franchise list order is unchanged" do
    stub_franchise_goal(scorer_goals: 330)

    @worker.perform(@game_id, franchise_goal_play)

    assert_empty RodTheBot::Post.jobs
  end

  test "skips franchise lists outside the regular season" do
    stub_franchise_goal(scorer_goals: 322)

    @worker.perform("2025030111", franchise_goal_play)

    assert_empty RodTheBot::Post.jobs
  end

  test "keeps career milestones when the records site fails" do
    stub_franchise_goal(scorer_goals: 322, career_goals: 499)
    Nhl::RecordsClient.stubs(:franchise_skater_totals).raises(Nhl::RequestError, "HTTP 500")

    @worker.perform(@game_id, franchise_goal_play)

    posts = RodTheBot::Post.jobs.map { |job| job["args"].first }
    assert_equal 2, posts.size
    assert_includes posts.first, "500 career goals"
    assert_includes posts.last, "500 career points"
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
          "assist2PlayerId" => nil,
          "eventOwnerTeamId" => 12
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

      Nhl::GameClient.stubs(:play_by_play).returns(feed)

      # Mock roster data
      Nhl::GameInfo.stubs(:roster).returns({
        8482093 => {number: 24, name: "Seth Jarvis", team_id: 12},
        8476906 => {number: 65, name: "William Carrier", team_id: 12}
      })
      Nhl::PlayerDirectory.stubs(:for_game).returns(Nhl::PlayerDirectory.new([
        Nhl::PlayerIdentity.new(id: 8482093, first_name: "Seth", last_name: "Jarvis", sweater_number: 24, team_id: 12),
        Nhl::PlayerIdentity.new(id: 8476906, first_name: "William", last_name: "Carrier", sweater_number: 65, team_id: 12)
      ]))

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
          "assist2PlayerId" => nil,
          "eventOwnerTeamId" => 12
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

      Nhl::GameClient.stubs(:play_by_play).returns(feed)

      # Mock roster data
      Nhl::GameInfo.stubs(:roster).returns({
        8482093 => {number: 24, name: "Seth Jarvis", team_id: 12}
      })
      Nhl::PlayerDirectory.stubs(:for_game).returns(Nhl::PlayerDirectory.new([
        Nhl::PlayerIdentity.new(id: 8476906, first_name: "William", last_name: "Carrier", sweater_number: 65, team_id: 12),
        Nhl::PlayerIdentity.new(id: 8482093, first_name: "Seth", last_name: "Jarvis", sweater_number: 24, team_id: 12)
      ]))

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
          "assist2PlayerId" => nil,
          "eventOwnerTeamId" => 12
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

      Nhl::GameClient.stubs(:play_by_play).returns(feed)

      # Mock roster data
      Nhl::GameInfo.stubs(:roster).returns({
        8476906 => {number: 65, name: "William Carrier", team_id: 12},
        8482093 => {number: 24, name: "Seth Jarvis", team_id: 12}
      })
      Nhl::PlayerDirectory.stubs(:for_game).returns(Nhl::PlayerDirectory.new([
        Nhl::PlayerIdentity.new(id: 8476906, first_name: "William", last_name: "Carrier", sweater_number: 65, team_id: 12),
        Nhl::PlayerIdentity.new(id: 8482093, first_name: "Seth", last_name: "Jarvis", sweater_number: 24, team_id: 12)
      ]))

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

  test "check_goal_milestones ignores opposing team goals" do
    VCR.use_cassette("milestone_checker_opponent_goal") do
      play = {
        "typeDescKey" => "goal",
        "eventId" => 500,
        "details" => {
          "scoringPlayerId" => 9999999,
          "assist1PlayerId" => nil,
          "assist2PlayerId" => nil,
          "eventOwnerTeamId" => 99 # Opponent team
        }
      }

      REDIS.set("pregame:#{@game_id}:player:9999999:goals", 49)
      REDIS.set("pregame:#{@game_id}:player:9999999:points", 99)

      feed = {
        "plays" => [
          {
            "typeDescKey" => "goal",
            "eventId" => 500,
            "details" => {
              "scoringPlayerId" => 9999999
            }
          }
        ]
      }

      Nhl::GameClient.stubs(:play_by_play).returns(feed)
      Nhl::GameInfo.stubs(:roster).returns({})

      @worker.perform(@game_id, play)

      assert_equal 0, RodTheBot::Post.jobs.size, "Should not post milestones for opposing team goals"
    end
  end

  private

  def franchise_goal_play
    {"typeDescKey" => "goal", "eventId" => 50, "details" => {"scoringPlayerId" => 8478427, "eventOwnerTeamId" => 12}}
  end

  def stub_franchise_goal(scorer_goals:, career_goals: 322)
    Nhl::GameClient.stubs(:play_by_play).returns("plays" => [franchise_goal_play])
    Nhl::PlayerDirectory.stubs(:for_game).returns(Nhl::PlayerDirectory.new([
      Nhl::PlayerIdentity.new(id: 8478427, first_name: "Sebastian", last_name: "Aho", sweater_number: 20, team_id: 12)
    ]))
    %w[goals points assists].each { |stat| REDIS.set("pregame:#{@game_id}:player:8478427:#{stat}", career_goals) }
    REDIS.set("pregame:2025030111:player:8478427:goals", career_goals)
    REDIS.set("pregame:2025030111:player:8478427:points", career_goals)
    Nhl::RecordsClient.stubs(:franchise_skater_totals).with(26).returns([
      {player_id: 8446951, name: "Ron Francis", goals: 382, assists: 793, points: 1175},
      {player_id: 8470595, name: "Eric Staal", goals: 322, assists: 453, points: 775},
      {player_id: 8478427, name: "Sebastian Aho", goals: scorer_goals, assists: 417, points: 739}
    ])
  end
end
