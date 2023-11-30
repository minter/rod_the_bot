require "test_helper"
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
end

class GameStartWorkerTest < Minitest::Test
  def setup
    @game_start_worker = RodTheBot::GameStartWorker.new
    @game_id = "2023020339"
  end

  def test_find_starting_goalie_home
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_game_start") do
      feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")
      players = @game_start_worker.send(:build_players, feed)
      goalie = @game_start_worker.send(:find_starting_goalie, feed["homeTeam"], players)

      assert_equal "G", goalie[:position]
      assert_equal "Cam Talbot", goalie[:name]
    end
  end

  def test_find_home_goalie_record
    VCR.use_cassette("nhl_player_8475660_landing") do
      player_id = "8475660"
      record = @game_start_worker.send(:find_goalie_record, player_id)

      assert_match(/\(\d+-\d+-\d+, \d+\.\d+ GAA, \d+\.\d+ SV%\)/, record)
      assert_equal "(10-3-1, 2.02 GAA, 0.931 SV%)", record
    end
  end

  def test_find_away_goalie_record
    VCR.use_cassette("nhl_player_8479292_landing") do
      player_id = "8479292"
      record = @game_start_worker.send(:find_goalie_record, player_id)

      assert_match(/\(\d+-\d+-\d+, \d+\.\d+ GAA, \d+\.\d+ SV%\)/, record)
      assert_equal "(4-2-0, 2.51 GAA, 0.926 SV%)", record
    end
  end

  def test_find_officials
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_landing") do
      officials = @game_start_worker.send(:find_officials, @game_id)

      assert_equal 2, officials[:referees].size
      assert_equal 2, officials[:lines].size
    end
  end

  def test_post
    VCR.insert_cassette("nhl_game_#{@game_id}_gamecenter_pbp_game_start")
    VCR.insert_cassette("nhl_game_#{@game_id}_gamecenter_landing")
    VCR.insert_cassette("nhl_player_8475660_landing")
    feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")
    players = @game_start_worker.send(:build_players, feed)
    home_goalie = @game_start_worker.send(:find_starting_goalie, feed["homeTeam"], players)
    away_goalie = @game_start_worker.send(:find_starting_goalie, feed["awayTeam"], players)
    home_goalie_record = @game_start_worker.send(:find_goalie_record, home_goalie[:id])
    away_goalie_record = @game_start_worker.send(:find_goalie_record, away_goalie[:id])
    officials = @game_start_worker.send(:find_officials, @game_id)
    post = @game_start_worker.send(:format_post, feed, home_goalie, away_goalie, officials, home_goalie_record, away_goalie_record)
    expected_output = <<~POST
      🚦 It's puck drop at Crypto.com Arena for Capitals at Kings!
      
      Starting Goalies:
      LAK: Cam Talbot (10-3-1, 2.02 GAA, 0.931 SV%)
      WSH: Charlie Lindgren (4-2-0, 2.51 GAA, 0.926 SV%)
      
      Refs: Brian Pochmara, Jake Brenk
      Lines: Tyson Baker, Ben O'Quinn
    POST
    assert_equal expected_output, post
    VCR.eject_cassette(name: "nhl_game_#{@game_id}_gamecenter_pbp")
    VCR.eject_cassette(name: "nhl_game_#{@game_id}_gamecenter_landing")
    VCR.eject_cassette(name: "nhl_player_8475660_landing")
  end
end
