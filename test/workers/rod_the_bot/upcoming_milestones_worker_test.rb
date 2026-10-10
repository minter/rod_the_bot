require "test_helper"

class RodTheBot::UpcomingMilestonesWorkerTest < ActiveSupport::TestCase
  AHO = 8478427
  BLAKE = 8482809
  ANDERSEN = 8475883

  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::UpcomingMilestonesWorker.new
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
    ENV["TEAM_HASHTAGS"] = "#LetsGoCanes #CauseChaos"
    Nhl::SeasonCalendar.stubs(:preseason?).returns(false)
    Nhl::SeasonCalendar.stubs(:offseason?).returns(false)
    Nhl::SeasonCalendar.stubs(:postseason?).returns(false)
  end

  def teardown
    Sidekiq::Worker.clear_all
  end

  test "perform skips during preseason" do
    Nhl::SeasonCalendar.stubs(:preseason?).returns(true)
    Nhl::Roster.expects(:for).never

    @worker.perform

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform skips during offseason" do
    Nhl::SeasonCalendar.stubs(:offseason?).returns(true)
    Nhl::Roster.expects(:for).never

    @worker.perform

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform posts roster milestones from regular season career totals" do
    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      stub_career_totals(:regularSeason, AHO => {"assists" => 499}, BLAKE => {"goals" => 98}, ANDERSEN => {"wins" => 298})

      @worker.perform

      assert_equal 1, RodTheBot::Post.jobs.size
      post_content = RodTheBot::Post.jobs.first["args"].first

      assert_match(/\A🎯 Upcoming Milestones:\n\n🔥 #20 Sebastian Aho: 1 assist away from 500/, post_content)
      assert_match(/⚡ #53 Jackson Blake: 2 goals away from 100/, post_content)
      assert_match(/⚡ #31 Frederik Andersen: 2 wins away from 300/, post_content)
    end
  end

  test "perform reads playoff career totals in the postseason" do
    Nhl::SeasonCalendar.stubs(:postseason?).returns(true)

    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      stub_career_totals(:playoffs, AHO => {"points" => 97})

      @worker.perform

      post_content = RodTheBot::Post.jobs.first["args"].first
      assert_match(/🎯 Upcoming Milestones \(Playoffs\):/, post_content)
      assert_match(/⚡ #20 Sebastian Aho: 3 points away from 100/, post_content)
    end
  end

  test "perform does not post when nobody is close" do
    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      stub_career_totals(:regularSeason)

      @worker.perform

      assert_equal 0, RodTheBot::Post.jobs.size
    end
  end

  test "perform threads long milestone lists under the character limit" do
    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      skaters = Nhl::Roster.for("CAR").values.reject { |player| player[:positionCode] == "G" }.first(10)
      stub_career_totals(:regularSeason, skaters.to_h { |player| [player[:id], {"assists" => 49}] })

      @worker.perform

      assert_operator RodTheBot::Post.jobs.size, :>, 1
      RodTheBot::Post.jobs.each do |job|
        assert_operator job["args"].first.length + ENV["TEAM_HASHTAGS"].length + 1, :<=, 300
      end
    end
  end

  test "perform raises career total failures for Sidekiq retry" do
    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      Nhl::PlayerClient.stubs(:career_totals).raises(Nhl::RequestError, "landing unavailable")

      assert_raises(Nhl::RequestError) { @worker.perform }
      assert_equal 0, RodTheBot::Post.jobs.size
    end
  end

  private

  def stub_career_totals(season_type, totals_by_player = {})
    Nhl::PlayerClient.stubs(:career_totals).with(anything, season_type: season_type).returns({})
    totals_by_player.each do |player_id, totals|
      Nhl::PlayerClient.stubs(:career_totals).with(player_id, season_type: season_type).returns(totals)
    end
  end
end
