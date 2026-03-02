require "test_helper"
require "vcr"

class RodTheBot::ShootoutWorkerTest < ActiveSupport::TestCase
  def setup
    @worker = RodTheBot::ShootoutWorker.new
    @game_id = 2025020934
    Sidekiq::Worker.clear_all
  end

  test "perform posts all rounds from VCR landing feed" do
    VCR.use_cassette("nhl_game_#{@game_id}_landing") do
      @worker.perform(@game_id)
    end

    assert_equal 3, RodTheBot::Post.jobs.size
    assert_equal 0, RodTheBot::ShootoutWorker.jobs.size

    # Round 1: standalone post
    round1_job = RodTheBot::Post.jobs[0]
    assert_match(/Shootout - Round 1/, round1_job["args"][0])
    assert_match(/PIT: A. Mantha ❌/, round1_job["args"][0])
    assert_match(/NYR: V. Trocheck ✅/, round1_job["args"][0])
    assert_equal "shootout:#{@game_id}:round:1", round1_job["args"][1]
    assert_nil round1_job["args"][2] # no parent_key

    # Round 2: reply to round 1
    round2_job = RodTheBot::Post.jobs[1]
    assert_match(/Shootout - Round 2/, round2_job["args"][0])
    assert_match(/PIT: E. Chinakhov ❌/, round2_job["args"][0])
    assert_match(/NYR: J.T. Miller ❌/, round2_job["args"][0])
    assert_equal "shootout:#{@game_id}:round:2", round2_job["args"][1]
    assert_equal "shootout:#{@game_id}:round:1", round2_job["args"][2]

    # Round 3: final round with winner, reply to round 2
    round3_job = RodTheBot::Post.jobs[2]
    assert_match(/Shootout - Round 3/, round3_job["args"][0])
    assert_match(/PIT: T. Novak ❌/, round3_job["args"][0])
    assert_match(/NYR wins the shootout 1-0!/, round3_job["args"][0])
    assert_equal "shootout:#{@game_id}:round:3", round3_job["args"][1]
    assert_equal "shootout:#{@game_id}:round:2", round3_job["args"][2]
  end

  test "perform skips already-posted rounds" do
    REDIS.set("shootout:#{@game_id}:rounds_posted", "2")

    VCR.use_cassette("nhl_game_#{@game_id}_landing") do
      @worker.perform(@game_id)
    end

    # Only round 3 should be posted
    assert_equal 1, RodTheBot::Post.jobs.size
    assert_match(/Shootout - Round 3/, RodTheBot::Post.jobs.first["args"][0])
  end

  test "rounds_posted counter is updated correctly" do
    VCR.use_cassette("nhl_game_#{@game_id}_landing") do
      @worker.perform(@game_id)
    end

    assert_equal "3", REDIS.get("shootout:#{@game_id}:rounds_posted")
  end

  test "format_round includes correct emoji for goals and saves" do
    VCR.use_cassette("nhl_game_#{@game_id}_landing") do
      @worker.perform(@game_id)
    end

    round1_post = RodTheBot::Post.jobs[0]["args"][0]
    assert_includes round1_post, "❌" # Mantha save
    assert_includes round1_post, "✅" # Trocheck goal
  end

  test "perform re-queues when game is not over" do
    feed = mock_live_feed(events: default_shootout_events.first(2))
    NhlApi.stubs(:fetch_landing_feed).returns(feed)

    @worker.perform(@game_id)

    assert_equal 1, RodTheBot::Post.jobs.size
    assert_equal 1, RodTheBot::ShootoutWorker.jobs.size

    requeue_job = RodTheBot::ShootoutWorker.jobs.first
    assert_equal [@game_id, 1], requeue_job["args"]
  end

  test "perform re-queues when shootout data is not yet available" do
    feed = mock_live_feed(events: nil, no_shootout: true)
    NhlApi.stubs(:fetch_landing_feed).returns(feed)

    @worker.perform(@game_id, 0)

    assert_equal 0, RodTheBot::Post.jobs.size
    assert_equal 1, RodTheBot::ShootoutWorker.jobs.size
    assert_equal [@game_id, 1], RodTheBot::ShootoutWorker.jobs.first["args"]
  end

  test "perform does not re-queue after max retries" do
    feed = mock_live_feed(events: nil, no_shootout: true)
    NhlApi.stubs(:fetch_landing_feed).returns(feed)

    @worker.perform(@game_id, RodTheBot::ShootoutWorker::MAX_RETRIES)

    assert_equal 0, RodTheBot::Post.jobs.size
    assert_equal 0, RodTheBot::ShootoutWorker.jobs.size
  end

  test "perform does not post incomplete rounds during live game" do
    feed = mock_live_feed(events: default_shootout_events.first(1))
    NhlApi.stubs(:fetch_landing_feed).returns(feed)

    @worker.perform(@game_id)

    assert_equal 0, RodTheBot::Post.jobs.size
    assert_equal 1, RodTheBot::ShootoutWorker.jobs.size
  end

  test "perform handles API error gracefully" do
    NhlApi.stubs(:fetch_landing_feed).raises(NhlApi::APIError.new("timeout"))

    @worker.perform(@game_id, 0)

    assert_equal 0, RodTheBot::Post.jobs.size
    assert_equal 1, RodTheBot::ShootoutWorker.jobs.size
  end

  private

  def mock_live_feed(events:, no_shootout: false)
    shootout = if no_shootout
      nil
    else
      {
        "liveScore" => {"home" => 1, "away" => 0},
        "events" => events
      }
    end

    {
      "gameState" => "LIVE",
      "awayTeam" => {"abbrev" => "PIT"},
      "homeTeam" => {"abbrev" => "NYR"},
      "summary" => {"shootout" => shootout}
    }
  end

  def default_shootout_events
    [
      {"sequence" => 1, "teamAbbrev" => {"default" => "PIT"}, "firstName" => {"default" => "Anthony"}, "lastName" => {"default" => "Mantha"}, "result" => "save", "gameWinner" => false, "homeScore" => 0, "awayScore" => 0},
      {"sequence" => 2, "teamAbbrev" => {"default" => "NYR"}, "firstName" => {"default" => "Vincent"}, "lastName" => {"default" => "Trocheck"}, "result" => "goal", "gameWinner" => true, "homeScore" => 1, "awayScore" => 0},
      {"sequence" => 3, "teamAbbrev" => {"default" => "PIT"}, "firstName" => {"default" => "Egor"}, "lastName" => {"default" => "Chinakhov"}, "result" => "save", "gameWinner" => false, "homeScore" => 1, "awayScore" => 0},
      {"sequence" => 4, "teamAbbrev" => {"default" => "NYR"}, "firstName" => {"default" => "J.T."}, "lastName" => {"default" => "Miller"}, "result" => "save", "gameWinner" => false, "homeScore" => 1, "awayScore" => 0},
      {"sequence" => 5, "teamAbbrev" => {"default" => "PIT"}, "firstName" => {"default" => "Tommy"}, "lastName" => {"default" => "Novak"}, "result" => "save", "gameWinner" => false, "homeScore" => 1, "awayScore" => 0}
    ]
  end
end
