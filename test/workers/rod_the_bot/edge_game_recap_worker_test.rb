require "test_helper"

class RodTheBot::EdgeGameRecapWorkerTest < ActiveSupport::TestCase
  GAME = 2026020321
  PLAYERS = {19 => %w[K'Andre Miller], 20 => %w[Sebastian Aho], 53 => %w[Jackson Blake], 4 => %w[Shayne Gostisbehere]}.freeze

  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EdgeGameRecapWorker.new
    ENV["NHL_TEAM_ID"] = "12"
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
    Timecop.freeze(Time.use_zone(ENV.fetch("TIME_ZONE")) { Time.zone.local(2026, 11, 15, 10) })

    Nhl::SeasonCalendar.stubs(:preseason?).returns(false)
    Nhl::ScheduleClient.stubs(:todays_game).with(date: Date.new(2026, 11, 14)).returns(scheduled_game)
    Nhl::GameClient.stubs(:boxscore).with(GAME).returns(boxscore)
    Nhl::PlayerDirectory.stubs(:for_game).with(GAME).returns(directory)

    Nhl::EdgeClient.stubs(:fetch_team_skating_distance_detail).with(12, game_id: GAME, fresh: true).returns(team_distance)
    Nhl::EdgeClient.stubs(:fetch_team_skating_distance_detail).with(55, game_id: GAME, fresh: true).returns(distance(44.9257))
    Nhl::EdgeClient.stubs(:fetch_team_shot_speed_detail).with(12, game_id: GAME, fresh: true)
      .returns({"hardestShots" => [{"gameCenterLink" => link, "player" => {"id" => 4}, "shotSpeed" => {"imperial" => 91.98}}]})
    Nhl::EdgeClient.stubs(:fetch_team_skating_speed_detail).with(12, game_id: GAME, fresh: true).returns({"topSkatingSpeeds" => []})
    {19 => 3.0844, 20 => 2.9409, 53 => 2.7701, 4 => 2.7554}.each do |player_id, miles|
      Nhl::EdgeClient.stubs(:fetch_skater_skating_distance_detail).with(player_id, game_id: GAME, fresh: true).returns(distance(miles, seconds: 1200))
    end
  end

  def teardown
    Timecop.return
  end

  test "posts a thread for yesterday's game" do
    @worker.perform

    posts = RodTheBot::Post.jobs
    assert_equal 3, posts.size
    assert posts[0]["args"][0].start_with?("⛸️ EDGE recap: Hurricanes vs. Kraken\n\nHurricanes skated 45.28 mi (fewest in their last 6 games)\nKraken: 44.93 mi")
    assert_equal "edge_recap_#{GAME}:1", posts[0]["args"][1]["key"]
    assert_includes posts[1]["args"][0], "#19 K'Andre Miller: 3.08 mi in 20:00"
    assert_equal "edge_recap_#{GAME}:1", posts[1]["args"][1]["parent_key"]
    assert_includes posts[2]["args"][0], "💥 #4 Shayne Gostisbehere: 91.98 mph shot (hardest)"
  end

  test "titles a road game from the tracked team's side" do
    Nhl::GameClient.stubs(:boxscore).with(GAME).returns(boxscore(tracked_side: "awayTeam"))

    @worker.perform

    assert RodTheBot::Post.jobs[0]["args"][0].start_with?("⛸️ EDGE recap: Hurricanes at Kraken")
  end

  test "does nothing without a game yesterday" do
    Nhl::ScheduleClient.stubs(:todays_game).returns(nil)

    @worker.perform

    assert_nothing_enqueued
  end

  test "does nothing in the preseason" do
    Nhl::SeasonCalendar.stubs(:preseason?).returns(true)

    @worker.perform

    assert_nothing_enqueued
  end

  test "does nothing when the game was not played to a final" do
    [{"gameState" => "FUT"}, {"gameScheduleState" => "PPD"}, {"gameType" => 1}].each do |change|
      Nhl::ScheduleClient.stubs(:todays_game).returns(scheduled_game.merge(change))

      @worker.perform

      assert_nothing_enqueued
    end
  end

  test "reschedules when EDGE has not published the game" do
    Nhl::EdgeClient.stubs(:fetch_team_skating_distance_detail).with(12, game_id: GAME, fresh: true).returns(distance(45.9, game_id: 2026020309))

    @worker.perform

    assert_equal 0, RodTheBot::Post.jobs.size
    job = RodTheBot::EdgeGameRecapWorker.jobs.sole
    assert_equal [1], job["args"]
    assert_in_delta 30.minutes.from_now.to_f, job["at"], 1
  end

  test "posts on a later attempt once the data lands" do
    @worker.perform(3)

    assert_equal 3, RodTheBot::Post.jobs.size
  end

  test "gives up after the last attempt" do
    Nhl::EdgeClient.stubs(:fetch_team_skating_distance_detail).with(12, game_id: GAME, fresh: true).returns(nil)
    Rails.logger.expects(:warn).with(regexp_matches(/#{GAME}/o))

    @worker.perform(6)

    assert_nothing_enqueued
  end

  test "skips a skater whose data fails" do
    Nhl::EdgeClient.stubs(:fetch_skater_skating_distance_detail).with(19, game_id: GAME, fresh: true).raises(Nhl::RequestError, "boom")

    @worker.perform

    skaters = RodTheBot::Post.jobs[1]["args"][0]
    refute_includes skaters, "Miller"
    assert_includes skaters, "#20 Sebastian Aho"
  end

  test "posts without season marks when shot and speed data fail" do
    Nhl::EdgeClient.stubs(:fetch_team_shot_speed_detail).raises(Nhl::RequestError, "boom")
    Nhl::EdgeClient.stubs(:fetch_team_skating_speed_detail).raises(Nhl::RequestError, "boom")

    @worker.perform

    assert_equal 2, RodTheBot::Post.jobs.size
  end

  test "posts without the opponent line when opponent data fails" do
    Nhl::EdgeClient.stubs(:fetch_team_skating_distance_detail).with(55, game_id: GAME, fresh: true).raises(Nhl::RequestError, "boom")

    @worker.perform

    refute_includes RodTheBot::Post.jobs[0]["args"][0], "Kraken:"
  end

  test "raises when team distance fails" do
    Nhl::EdgeClient.stubs(:fetch_team_skating_distance_detail).with(12, game_id: GAME, fresh: true).raises(Nhl::RequestError, "boom")

    assert_raises(Nhl::RequestError) { @worker.perform }
    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "does not post twice for the same game" do
    @worker.perform
    @worker.perform

    assert_equal 3, RodTheBot::Post.jobs.size
  end

  test "releases the claim when enqueuing fails" do
    RodTheBot::PostThread.stubs(:enqueue).raises(RuntimeError, "redis down").then.returns(nil)

    assert_raises(RuntimeError) { @worker.perform }
    RodTheBot::PostThread.expects(:enqueue).once
    @worker.perform
  end

  private

  def assert_nothing_enqueued
    assert_equal 0, RodTheBot::Post.jobs.size
    assert_equal 0, RodTheBot::EdgeGameRecapWorker.jobs.size
  end

  def link(game_id = GAME)
    "/gamecenter/sea-vs-car/2026/11/14/#{game_id}"
  end

  def distance(miles, seconds: 17_800, game_id: GAME)
    {"skatingDistanceLast10" => [{"gameCenterLink" => link(game_id), "distanceSkatedAll" => {"imperial" => miles}, "toiAll" => seconds}]}
  end

  def team_distance
    earlier = (1..5).map { |n| distance(46.0, game_id: GAME - n)["skatingDistanceLast10"].first }
    {"skatingDistanceLast10" => distance(45.2762)["skatingDistanceLast10"] + earlier}
  end

  def scheduled_game
    {"id" => GAME, "gameType" => 2, "gameState" => "OFF", "gameScheduleState" => "OK"}
  end

  def boxscore(tracked_side: "homeTeam")
    other_side = (tracked_side == "homeTeam") ? "awayTeam" : "homeTeam"
    {
      tracked_side => {"id" => 12, "commonName" => {"default" => "Hurricanes"}},
      other_side => {"id" => 55, "commonName" => {"default" => "Kraken"}},
      "playerByGameStats" => {
        tracked_side => {"forwards" => [{"playerId" => 20}, {"playerId" => 53}], "defense" => [{"playerId" => 19}, {"playerId" => 4}], "goalies" => [{"playerId" => 99}]},
        other_side => {"forwards" => [{"playerId" => 500}], "defense" => []}
      }
    }
  end

  def directory
    numbers = {19 => 19, 20 => 20, 53 => 53, 4 => 4}
    Nhl::PlayerDirectory.new(PLAYERS.map do |id, (first, last)|
      Nhl::PlayerIdentity.new(id: id, first_name: first, last_name: last, sweater_number: numbers[id])
    end)
  end
end
