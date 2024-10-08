require "test_helper"

class NhlApiTest < ActiveSupport::TestCase
  setup do
    @game_id = "2023020339"
    @player_id = "8479973"
    @team_abbreviation = "CAR"
  end

  test "fetch_pbp_feed" do
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp") do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      assert_kind_of Hash, feed
      assert_includes feed.keys, "plays"
    end
  end

  test "fetch_play" do
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp") do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      assert_kind_of Hash, feed, "Feed should be a Hash"
      assert feed.key?("plays"), "Feed should have a 'plays' key"
      assert_kind_of Array, feed["plays"], "'plays' should be an Array"

      skip("No plays found in the feed") if feed["plays"].empty?

      play = feed["plays"].first
      play_id = play["eventId"].to_s
      fetched_play = NhlApi.fetch_play(@game_id, play_id)

      assert_equal play_id, fetched_play["eventId"].to_s
    end
  end

  test "fetch_boxscore_feed" do
    VCR.use_cassette("nhl_game_#{@game_id}_boxscore") do
      feed = NhlApi.fetch_boxscore_feed(@game_id)
      assert_kind_of Hash, feed
      assert_includes feed.keys, "id"  # Changed from "boxscore" to "id"
    end
  end

  test "fetch_landing_feed" do
    VCR.use_cassette("nhl_game_#{@game_id}_landing") do
      feed = NhlApi.fetch_landing_feed(@game_id)
      assert_kind_of Hash, feed
      assert_includes feed.keys, "gameType"
    end
  end

  test "fetch_player_landing_feed" do
    VCR.use_cassette("nhl_player_#{@player_id}_landing") do
      feed = NhlApi.fetch_player_landing_feed(@player_id)
      assert_kind_of Hash, feed
      assert_includes feed.keys, "featuredStats"
    end
  end

  test "fetch_right_rail_feed" do
    VCR.use_cassette("nhl_game_#{@game_id}_right_rail") do
      feed = NhlApi.fetch_right_rail_feed(@game_id)
      assert_kind_of Hash, feed
      assert_includes feed.keys, "gameInfo"
    end
  end

  test "fetch_team_schedule" do
    date = "2023-11-30"
    VCR.use_cassette("nhl_schedule_#{date}") do
      schedule = NhlApi.fetch_team_schedule(date: date)
      assert_kind_of Hash, schedule
      assert_includes schedule.keys, "games"
    end
  end

  test "fetch_roster" do
    VCR.use_cassette("nhl_roster_#{@team_abbreviation}") do
      roster = NhlApi.fetch_roster(@team_abbreviation)
      assert_kind_of Hash, roster
      assert_includes roster.keys, "forwards"
    end
  end

  test "fetch_standings" do
    VCR.use_cassette("nhl_standings") do
      standings = NhlApi.fetch_standings
      assert_kind_of Hash, standings
      assert_includes standings.keys, "standings"
    end
  end

  test "fetch_scores" do
    date = "2023-11-29"
    VCR.use_cassette("nhl_scores_#{date}") do
      scores = NhlApi.fetch_scores(date: date)
      assert_kind_of Array, scores
      assert scores.all? { |game| game["gameDate"] == date }
    end
  end

  test "todays_game" do
    date = "2023-11-30"
    VCR.use_cassette("nhl_schedule_#{date}") do
      game = NhlApi.todays_game(date: date)
      assert_kind_of Hash, game
      assert_equal date, game["gameDate"]
    end
  end

  test "roster" do
    VCR.use_cassette("nhl_roster_#{@team_abbreviation}") do
      roster = NhlApi.roster(@team_abbreviation)
      assert_kind_of Hash, roster
      assert roster.values.all? { |player| player.key?(:fullName) }
    end
  end

  test "team_standings" do
    VCR.use_cassette("nhl_standings") do
      standings = NhlApi.team_standings(@team_abbreviation)
      assert_kind_of Hash, standings
      assert_includes standings.keys, :division_name
    end
  end

  test "officials" do
    VCR.use_cassette("nhl_game_#{@game_id}_right_rail") do
      officials = NhlApi.officials(@game_id)
      assert_kind_of Hash, officials
      assert_includes officials.keys, :referees
      assert_includes officials.keys, :linesmen
    end
  end

  test "splits" do
    VCR.use_cassette("nhl_game_#{@game_id}_right_rail") do
      splits = NhlApi.splits(@game_id)
      assert_kind_of Hash, splits
      assert splits.values.all? { |split| split.key?(:away) && split.key?(:home) }
    end
  end

  test "game_rosters" do
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp") do
      rosters = NhlApi.game_rosters(@game_id)
      assert_kind_of Hash, rosters
      assert rosters.values.all? { |player| player.key?(:name) }
    end
  end

  test "current_season" do
    VCR.use_cassette("nhl_season") do
      season = NhlApi.current_season
      assert_kind_of String, season
      assert_match(/\d{8}/, season)
    end
  end

  test "postseason?" do
    VCR.use_cassette("nhl_postseason_carousel") do
      is_postseason = NhlApi.postseason?
      assert_includes [true, false], is_postseason
    end
  end

  test "preseason?" do
    VCR.use_cassette("nhl_season") do
      NhlApi.stubs(:current_season).returns("20232024")

      # Test when it is preseason
      assert NhlApi.preseason?("20242025"), "Should be preseason when target season is 20242025"

      # Test when it is not preseason
      refute NhlApi.preseason?("20232024"), "Should not be preseason when target season matches current season"

      # Test with different current season
      NhlApi.stubs(:current_season).returns("20242025")
      refute NhlApi.preseason?("20242025"), "Should not be preseason when both seasons are 20242025"
    end
  end

  test "teams" do
    VCR.use_cassette("nhl_teams") do
      teams = NhlApi.teams
      assert_kind_of Hash, teams
      assert_operator teams.size, :>, 0

      # Check structure of a team entry
      team = teams.values.first
      assert_includes team.keys, :id
      assert_includes team.keys, :fullName
      assert_includes team.keys, :triCode
    end
  end
end
