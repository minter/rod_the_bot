require "test_helper"
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
end

class GameStartWorkerTest < Minitest::Test
  def setup
    @game_start_worker = RodTheBot::GameStartWorker.new
    @game_id = "2023030246"
  end

  def test_find_starting_goalie_home
    # VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_game_start") do
    feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")
    @game_start_worker.instance_variable_set(:@feed, feed)
    goalie = @game_start_worker.send(:find_starting_goalie, feed["homeTeam"])

    assert_equal "G", goalie[:position]
    assert_equal "Stuart Skinner", goalie[:name]
    # end
  end

  def test_find_home_goalie_record
    # VCR.use_cassette("nhl_player_8479973_landing") do
    player_id = "8479973"
    record = @game_start_worker.send(:find_goalie_record, player_id)

    assert_match(/\(\d+-\d+-\d+, \d+\.\d+ GAA, \d+\.\d+ SV%\)/, record)
    assert_equal "(10-3-1, 2.02 GAA, 0.931 SV%)", record
    # end
  end

  def test_find_away_goalie_record
    # VCR.use_cassette("nhl_player_8481668_landing") do
    player_id = "8481668"
    record = @game_start_worker.send(:find_goalie_record, player_id)

    assert_match(/\(\d+-\d+-\d+, \d+\.\d+ GAA, \d+\.\d+ SV%\)/, record)
    assert_equal "(4-2-0, 2.51 GAA, 0.926 SV%)", record
    # end
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
    VCR.insert_cassette("nhl_player_8479973_landing")
    VCR.insert_cassette("nhl_player_8481668_landing")
    @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")
    home_goalie = @game_start_worker.send(:find_starting_goalie, @feed["homeTeam"])
    away_goalie = @game_start_worker.send(:find_starting_goalie, @feed["awayTeam"])
    home_goalie_record = @game_start_worker.send(:find_goalie_record, home_goalie[:id])
    away_goalie_record = @game_start_worker.send(:find_goalie_record, away_goalie[:id])
    officials = @game_start_worker.send(:find_officials, @game_id)
    post = @game_start_worker.send(:format_post, @feed, home_goalie, away_goalie, officials, home_goalie_record, away_goalie_record)
    expected_output = <<~POST
      🚦 It's puck drop at Rogers Place for Canucks at Oilers!

      Starting Goalies:
      EDM: #74 S. Skinner (5-3-0, 3.22 GAA, 0.877 SV%)
      VAN: #31 A. Silovs (5-3-0, 2.62 GAA, 0.907 SV%)
      
      Refs: Garrett Rank, Jean Hebert
      Lines: Shandor Alphonso, Jonny Murray
    POST
    assert_equal expected_output, post
    VCR.eject_cassette(name: "nhl_game_#{@game_id}_gamecenter_pbp")
    VCR.eject_cassette(name: "nhl_game_#{@game_id}_gamecenter_landing")
    VCR.eject_cassette(name: "nhl_player_8479973_landing")
    VCR.eject_cassette(name: "nhl_player_8481668_landing")
  end
end
