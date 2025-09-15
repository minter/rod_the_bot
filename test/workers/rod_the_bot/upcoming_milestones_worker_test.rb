require "test_helper"

class RodTheBot::UpcomingMilestonesWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::UpcomingMilestonesWorker.new
    ENV["NHL_TEAM_ID"] = "12"  # Carolina Hurricanes
    ENV["NHL_TEAM_ABBREVIATION"] = "CAR"
    ENV["TEAM_HASHTAGS"] = "#LetsGoCanes #CauseChaos"
  end

  def teardown
    Sidekiq::Worker.clear_all
  end

  test "perform skips during preseason" do
    skip "VCR cassette issue - needs schedule API call recorded"
    NhlApi.stubs(:preseason?).returns(true)
    NhlApi.stubs(:offseason?).returns(false)

    @worker.perform

    assert_equal 0, RodTheBot::Post.jobs.size
  end

  test "perform skips during offseason" do
    skip "VCR cassette issue - needs schedule API call recorded"
    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      NhlApi.stubs(:preseason?).returns(false)
      NhlApi.stubs(:offseason?).returns(true)

      @worker.perform

      assert_equal 0, RodTheBot::Post.jobs.size
    end
  end

  test "perform with regular season milestones" do
    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      NhlApi.stubs(:preseason?).returns(false)
      NhlApi.stubs(:offseason?).returns(false)
      NhlApi.stubs(:postseason?).returns(false)
      NhlApi.stubs(:todays_game).returns({"gameScheduleState" => "OK"})

      # Get actual roster to use real player IDs
      roster = NhlApi.roster("CAR")
      real_player_ids = roster.keys.map(&:to_s)

      # Mock the milestone data for Carolina Hurricanes using real player IDs
      mock_skater_milestones = {
        "data" => [
          {
            "id" => 1,
            "assists" => 49,
            "currentTeamId" => 12,
            "firstName" => "Jaccob",
            "lastName" => "Slavin",
            "milestone" => "Assists",
            "milestoneAmount" => 50,
            "playerFullName" => "Jaccob Slavin",
            "playerId" => real_player_ids.first.to_i,
            "points" => 299,
            "teamAbbrev" => "CAR",
            "teamCommonName" => "Hurricanes",
            "teamFullName" => "Carolina Hurricanes",
            "teamPlaceName" => "Carolina",
            "gameTypeId" => 2
          },
          {
            "id" => 2,
            "goals" => 98,
            "currentTeamId" => 12,
            "firstName" => "Jordan",
            "lastName" => "Martinook",
            "milestone" => "Goals",
            "milestoneAmount" => 100,
            "playerFullName" => "Jordan Martinook",
            "playerId" => real_player_ids.second.to_i,
            "points" => 195,
            "teamAbbrev" => "CAR",
            "teamCommonName" => "Hurricanes",
            "teamFullName" => "Carolina Hurricanes",
            "teamPlaceName" => "Carolina",
            "gameTypeId" => 2
          }
        ]
      }

      mock_goalie_milestones = {
        "data" => [
          {
            "id" => 1,
            "currentTeamId" => 12,
            "firstName" => "Frederik",
            "lastName" => "Andersen",
            "milestone" => "Wins",
            "milestoneAmount" => 300,
            "playerFullName" => "Frederik Andersen",
            "playerId" => real_player_ids.last.to_i,
            "wins" => 298,
            "teamAbbrev" => "CAR",
            "teamCommonName" => "Hurricanes",
            "teamFullName" => "Carolina Hurricanes",
            "teamPlaceName" => "Carolina",
            "gameTypeId" => 2
          }
        ]
      }

      # Mock the API calls
      @worker.expects(:fetch_skater_milestones).returns(mock_skater_milestones)
      @worker.expects(:fetch_goalie_milestones).returns(mock_goalie_milestones)

      @worker.perform

      assert_equal 1, RodTheBot::Post.jobs.size
      post_content = RodTheBot::Post.jobs.first["args"].first

      assert_match(/🎯 Upcoming Milestones:/, post_content)
      assert_match(/🔥 Jaccob Slavin: 1 assist away from 50/, post_content)
      assert_match(/⚡ Frederik Andersen: 2 wins away from 300/, post_content)
      assert_match(/⚡ Jordan Martinook: 2 goals away from 100/, post_content)
    end
  end

  test "perform with playoff milestones" do
    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      NhlApi.stubs(:preseason?).returns(false)
      NhlApi.stubs(:offseason?).returns(false)
      NhlApi.stubs(:postseason?).returns(true)
      NhlApi.stubs(:todays_game).returns({"gameScheduleState" => "OK"})

      # Mock playoff milestone data
      mock_skater_milestones = {
        "data" => [
          {
            "id" => 1,
            "assists" => 48,
            "currentTeamId" => 12,
            "firstName" => "Andrei",
            "lastName" => "Svechnikov",
            "milestone" => "Assists",
            "milestoneAmount" => 50,
            "playerFullName" => "Andrei Svechnikov",
            "playerId" => 8480830,
            "points" => 48,
            "teamAbbrev" => "CAR",
            "teamCommonName" => "Hurricanes",
            "teamFullName" => "Carolina Hurricanes",
            "teamPlaceName" => "Carolina",
            "gameTypeId" => 3
          }
        ]
      }

      mock_goalie_milestones = {
        "data" => [
          {
            "id" => 1,
            "currentTeamId" => 12,
            "firstName" => "Frederik",
            "lastName" => "Andersen",
            "milestone" => "Wins",
            "milestoneAmount" => 50,
            "playerFullName" => "Frederik Andersen",
            "playerId" => 8475883,
            "wins" => 48,
            "teamAbbrev" => "CAR",
            "teamCommonName" => "Hurricanes",
            "teamFullName" => "Carolina Hurricanes",
            "teamPlaceName" => "Carolina",
            "gameTypeId" => 3
          }
        ]
      }

      # Mock the API calls
      @worker.expects(:fetch_skater_milestones).returns(mock_skater_milestones)
      @worker.expects(:fetch_goalie_milestones).returns(mock_goalie_milestones)

      @worker.perform

      assert_equal 1, RodTheBot::Post.jobs.size
      post_content = RodTheBot::Post.jobs.first["args"].first

      assert_match(/🎯 Upcoming Milestones \(Playoffs\):/, post_content)
      assert_match(/⚡ Andrei Svechnikov: 2 assists away from 50/, post_content)
      assert_match(/⚡ Frederik Andersen: 2 wins away from 50/, post_content)
    end
  end

  test "perform with no upcoming milestones" do
    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      NhlApi.stubs(:preseason?).returns(false)
      NhlApi.stubs(:offseason?).returns(false)
      NhlApi.stubs(:postseason?).returns(false)
      NhlApi.stubs(:todays_game).returns({"gameScheduleState" => "OK"})

      # Mock empty milestone data
      mock_skater_milestones = {"data" => []}
      mock_goalie_milestones = {"data" => []}

      # Mock the API calls
      @worker.expects(:fetch_skater_milestones).returns(mock_skater_milestones)
      @worker.expects(:fetch_goalie_milestones).returns(mock_goalie_milestones)

      @worker.perform

      assert_equal 0, RodTheBot::Post.jobs.size
    end
  end

  test "post_milestones_in_threads creates multiple posts when needed" do
    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      NhlApi.stubs(:preseason?).returns(false)
      NhlApi.stubs(:offseason?).returns(false)
      NhlApi.stubs(:postseason?).returns(false)
      NhlApi.stubs(:todays_game).returns({"gameScheduleState" => "OK"})

      # Get actual roster to use real player IDs
      roster = NhlApi.roster("CAR")
      real_player_ids = roster.keys.map(&:to_s)

      # Mock many milestones to test threading using real player IDs
      mock_skater_milestones = {
        "data" => real_player_ids.first(10).map.with_index do |player_id, i|
          {
            "id" => i + 1,
            "assists" => 49,
            "currentTeamId" => 12,
            "firstName" => "Player",
            "lastName" => "Name#{i + 1}",
            "milestone" => "Assists",
            "milestoneAmount" => 50,
            "playerFullName" => "Player Name#{i + 1}",
            "playerId" => player_id.to_i,
            "points" => 299,
            "teamAbbrev" => "CAR",
            "teamCommonName" => "Hurricanes",
            "teamFullName" => "Carolina Hurricanes",
            "teamPlaceName" => "Carolina",
            "gameTypeId" => 2
          }
        end
      }

      mock_goalie_milestones = {"data" => []}

      # Mock the API calls
      @worker.expects(:fetch_skater_milestones).returns(mock_skater_milestones)
      @worker.expects(:fetch_goalie_milestones).returns(mock_goalie_milestones)

      @worker.perform

      # Should create multiple posts due to threading
      assert_operator RodTheBot::Post.jobs.size, :>=, 1

      # Check that all posts are under character limit
      hashtags = ENV["TEAM_HASHTAGS"] || ""
      hashtag_length = hashtags.empty? ? 0 : hashtags.length + 1 # +1 for newline

      RodTheBot::Post.jobs.each do |job|
        post_content = job["args"].first
        total_length = post_content.length + hashtag_length
        assert_operator total_length, :<=, 300, "Post exceeds character limit: #{total_length}"
      end
    end
  end

  test "get_current_roster_player_ids extracts player IDs correctly" do
    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      player_ids = @worker.send(:get_current_roster_player_ids)

      # Should extract player IDs from the actual roster data
      assert player_ids.is_a?(Array)
      assert player_ids.all? { |id| id.is_a?(String) }
      assert player_ids.size > 0
    end
  end

  test "get_upcoming_milestones filters by team and game type" do
    VCR.use_cassette("nhl_roster_CAR", allow_playback_repeats: true) do
      mock_skater_milestones = {
        "data" => [
          {
            "id" => 1,
            "assists" => 49,
            "currentTeamId" => 12,
            "firstName" => "Jaccob",
            "lastName" => "Slavin",
            "milestone" => "Assists",
            "milestoneAmount" => 50,
            "playerFullName" => "Jaccob Slavin",
            "playerId" => 8476453,
            "points" => 299,
            "teamAbbrev" => "CAR",
            "teamCommonName" => "Hurricanes",
            "teamFullName" => "Carolina Hurricanes",
            "teamPlaceName" => "Carolina",
            "gameTypeId" => 2
          },
          {
            "id" => 2,
            "assists" => 49,
            "currentTeamId" => 12,
            "firstName" => "Jaccob",
            "lastName" => "Slavin",
            "milestone" => "Assists",
            "milestoneAmount" => 50,
            "playerFullName" => "Jaccob Slavin",
            "playerId" => 8476453,
            "points" => 299,
            "teamAbbrev" => "CAR",
            "teamCommonName" => "Hurricanes",
            "teamFullName" => "Carolina Hurricanes",
            "teamPlaceName" => "Carolina",
            "gameTypeId" => 3
          },
          {
            "id" => 3,
            "assists" => 49,
            "currentTeamId" => 1,  # Different team
            "firstName" => "Other",
            "lastName" => "Player",
            "milestone" => "Assists",
            "milestoneAmount" => 50,
            "playerFullName" => "Other Player",
            "playerId" => 8476456,
            "points" => 299,
            "teamAbbrev" => "BOS",
            "teamCommonName" => "Bruins",
            "teamFullName" => "Boston Bruins",
            "teamPlaceName" => "Boston",
            "gameTypeId" => 2
          }
        ]
      }

      mock_goalie_milestones = {"data" => []}
      current_roster = ["8476453"]

      @worker.expects(:fetch_skater_milestones).returns(mock_skater_milestones)
      @worker.expects(:fetch_goalie_milestones).returns(mock_goalie_milestones)

      # Test regular season (gameTypeId: 2)
      milestones = @worker.send(:get_upcoming_milestones, 12, 2, current_roster)

      assert_equal 1, milestones.size
      assert_equal "Jaccob Slavin", milestones.first["playerFullName"]
      assert_equal 2, milestones.first["gameTypeId"]
    end
  end
end
