require "test_helper"

class RodTheBot::DraftPickWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @original_env = ENV.to_h
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
    ENV["NHL_TEAM_ID"] = "12"
    ENV.delete("TEAM_HASHTAGS")
    Time.zone = ENV["TIME_ZONE"]
    @worker = RodTheBot::DraftPickWorker.new
  end

  def teardown
    ENV.replace(@original_env)
  end

  def test_posts_selected_team_pick_on_inferred_draft_day
    Timecop.freeze(Date.new(2026, 6, 26)) do
      NhlApi.expects(:fetch_draft_picks).with(2026).returns(draft_data)
      NhlApi.expects(:fetch_draft_rankings).with(2026).returns(rankings)

      @worker.perform
    end

    assert_equal 1, RodTheBot::Post.jobs.size
    post = RodTheBot::Post.jobs.first["args"].first
    assert_includes post, "With pick No. 31 in Round 1 of the 2026 NHL Draft"
    assert_includes post, "the Carolina Hurricanes selected Canadian C Gavin McKenna"
    assert_includes post, "Ranking: 1st in North American Skaters"
    assert_includes post, "Height: 5'11\""
    assert_equal "1", REDIS.get("draft_pick:2026:31")
    assert_equal 1, RodTheBot::DraftPickWorker.jobs.size
  end

  def test_requeues_on_draft_day_before_draft_starts
    Timecop.freeze(Date.new(2026, 6, 26)) do
      NhlApi.expects(:fetch_draft_picks).with(2026).returns(draft_data(state: "fut"))
      NhlApi.expects(:fetch_draft_rankings).never

      @worker.perform
    end

    assert_equal 0, RodTheBot::Post.jobs.size
    assert_equal 1, RodTheBot::DraftPickWorker.jobs.size
  end

  def test_skips_before_inferred_draft_day
    Timecop.freeze(Date.new(2026, 6, 19)) do
      NhlApi.expects(:fetch_draft_picks).with(2026).returns(draft_data(state: "fut"))
      NhlApi.expects(:fetch_draft_rankings).never

      @worker.perform
    end

    assert_equal 0, RodTheBot::Post.jobs.size
    assert_equal 0, RodTheBot::DraftPickWorker.jobs.size
  end

  def test_splits_long_pick_post_into_thread_parts
    ENV["TEAM_HASHTAGS"] = "#Canes #NHLDraft"
    long_club_name = Array.new(60, "Long Club Name").join(" ")
    pick = car_pick.merge("amateurClubName" => long_club_name)

    Timecop.freeze(Date.new(2026, 6, 26)) do
      NhlApi.expects(:fetch_draft_picks).with(2026).returns(draft_data(picks: [pick]))
      NhlApi.expects(:fetch_draft_rankings).with(2026).returns(rankings)

      @worker.perform
    end

    assert_operator RodTheBot::Post.jobs.size, :>, 1
    RodTheBot::Post.jobs.each do |job|
      assert_operator "#{job["args"].first}\n#{ENV["TEAM_HASHTAGS"]}".length, :<=, 300
    end

    first_args = RodTheBot::Post.jobs.first["args"]
    second_args = RodTheBot::Post.jobs.second["args"]
    assert_equal "draft_pick:2026:31:post:1", first_args.second
    assert_equal "draft_pick:2026:31:post:1", second_args.third
  end

  def test_explicit_completed_draft_replay_processes_without_requeueing
    NhlApi.expects(:fetch_draft_picks).with(2025).returns(draft_data(year: 2025, state: "over"))
    NhlApi.expects(:fetch_draft_rankings).with(2025).returns(rankings)

    @worker.perform(2025, true)

    assert_equal 1, RodTheBot::Post.jobs.size
    assert_equal 0, RodTheBot::DraftPickWorker.jobs.size
    assert_equal "1", REDIS.get("draft_pick:2025:31")
  end

  def test_completed_draft_does_not_process_without_explicit_replay_flag
    Timecop.freeze(Date.new(2025, 6, 29)) do
      NhlApi.expects(:fetch_draft_picks).with(2025).returns(draft_data(year: 2025, state: "over"))
      NhlApi.expects(:fetch_draft_rankings).never

      @worker.perform
    end

    assert_equal 0, RodTheBot::Post.jobs.size
    assert_equal 0, RodTheBot::DraftPickWorker.jobs.size
  end

  private

  def draft_data(year: 2026, state: "live", picks: [car_pick, other_pick])
    {
      "broadcastStartTimeUTC" => "#{year}-06-26T23:00:00Z",
      "draftYear" => year,
      "state" => state,
      "picks" => picks
    }
  end

  def car_pick
    {
      "round" => 1,
      "pickInRound" => 31,
      "overallPick" => 31,
      "teamId" => 12,
      "teamAbbrev" => "CAR",
      "teamName" => {"default" => "Carolina Hurricanes"},
      "displayAbbrev" => {"default" => "CAR"},
      "teamPickHistory" => "CAR",
      "firstName" => {"default" => "Gavin"},
      "lastName" => {"default" => "McKenna"},
      "positionCode" => "C",
      "countryCode" => "CAN",
      "height" => 71,
      "weight" => 170,
      "amateurLeague" => "BIG10",
      "amateurClubName" => "Penn State"
    }
  end

  def other_pick
    car_pick.merge(
      "overallPick" => 32,
      "teamId" => 9,
      "teamAbbrev" => "OTT",
      "teamName" => {"default" => "Ottawa Senators"},
      "displayAbbrev" => {"default" => "OTT"}
    )
  end

  def rankings
    {
      north_american_skaters: [
        {
          "firstName" => "Gavin",
          "lastName" => "McKenna",
          "finalRank" => 1,
          "heightInInches" => 71,
          "weightInPounds" => 170,
          "shootsCatches" => "L",
          "birthDate" => "2007-12-20",
          "birthCity" => "Whitehorse",
          "birthStateProvince" => "YT",
          "birthCountry" => "CAN"
        }
      ]
    }
  end
end
