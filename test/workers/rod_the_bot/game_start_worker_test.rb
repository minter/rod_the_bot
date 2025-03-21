require "test_helper"

class RodTheBot::GameStartWorkerTest < ActiveSupport::TestCase
  def setup
    @game_start_worker = RodTheBot::GameStartWorker.new
    @game_id = "2024020478"
  end

  test "find_starting_goalie" do
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_game_start") do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      @game_start_worker.instance_variable_set(:@feed, feed)
      goalie = @game_start_worker.send(:find_starting_goalie, "homeTeam")

      assert_not_nil goalie
      assert_equal "L. Ullmark", goalie["name"]["default"]
    end
  end

  test "find_goalie_record" do
    VCR.use_cassette("nhl_player_8479973_landing") do
      player_id = "8479973"
      feed = NhlApi.fetch_pbp_feed(@game_id)
      @game_start_worker.instance_variable_set(:@feed, feed)
      record = @game_start_worker.send(:find_goalie_record, player_id)

      assert_match(/\(\d+-\d+-\d+, \d+\.\d+ GAA, \d+\.\d+ SV%\)/, record)
    end
  end

  test "format_main_post" do
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_game_start") do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      home_goalie = {"sweaterNumber" => "35", "name" => {"default" => "L. Ullmark"}}
      away_goalie = {"sweaterNumber" => "35", "name" => {"default" => "T. Jarry"}}
      home_goalie_record = "(5-3-0, 3.22 GAA, 0.877 SV%)"
      away_goalie_record = "(5-3-0, 2.62 GAA, 0.907 SV%)"

      post = @game_start_worker.send(:format_main_post, feed, home_goalie, home_goalie_record, away_goalie, away_goalie_record)

      assert_match(/🚦 It's puck drop at .+ for .+ at .+!/, post)
      assert_match(/Starting Goalies:/, post)
      assert_match(/PIT: #35 T. Jarry \(5-3-0, 2.62 GAA, 0.907 SV%\)/, post)
      assert_match(/OTT: #35 L. Ullmark \(5-3-0, 3.22 GAA, 0.877 SV%\)/, post)
    end
  end

  test "format_reply_post" do
    officials = {referees: ["Garrett Rank", "Jean Hebert"], linesmen: ["Shandor Alphonso", "Jonny Murray"]}
    scratches = "EDM: Player1, Player2\nVAN: Player3, Player4"

    post = @game_start_worker.send(:format_reply_post, officials, scratches)

    assert_match(/Officials:/, post)
    assert_match(/Referees: Garrett Rank, Jean Hebert/, post)
    assert_match(/Lines: Shandor Alphonso, Jonny Murray/, post)
    assert_match(/Scratches:\n\nEDM: Player1, Player2\nVAN: Player3, Player4/, post)
  end

  test "perform" do
    VCR.use_cassette("nhl_game_#{@game_id}_game_start_worker_perform") do
      NhlApi.expects(:fetch_pbp_feed).returns({
        "summary" => {
          "iceSurface" => {
            "homeTeam" => {"goalies" => [{"playerId" => "123", "name" => {"default" => "Home Goalie"}}]},
            "awayTeam" => {"goalies" => [{"playerId" => "456", "name" => {"default" => "Away Goalie"}}]}
          }
        },
        "gameType" => 2,
        "venue" => {"default" => "Test Arena"},
        "homeTeam" => {
          "name" => {"default" => "Home Team"},
          "abbrev" => "HOME",
          "commonName" => {"default" => "Home Team"}
        },
        "awayTeam" => {
          "name" => {"default" => "Away Team"},
          "abbrev" => "AWAY",
          "commonName" => {"default" => "Away Team"}
        },
        "startTime" => "2024-02-04T19:00:00Z"
      })
      NhlApi.expects(:officials).returns({referees: ["Ref1", "Ref2"], linesmen: ["Lines1", "Lines2"]})
      NhlApi.expects(:fetch_player_landing_feed).twice.returns({
        "featuredStats" => {
          "regularSeason" => {
            "subSeason" => {"wins" => 10, "losses" => 5, "otLosses" => 2, "goalsAgainstAvg" => 2.5, "savePctg" => 0.915}
          }
        }
      })
      NhlApi.expects(:fetch_player_landing_feed).twice.returns({
        "featuredStats" => {
          "regularSeason" => {
            "subSeason" => {"wins" => 10, "losses" => 5, "otLosses" => 2, "goalsAgainstAvg" => 2.5, "savePctg" => 0.915}
          }
        }
      })
      NhlApi.expects(:scratches).returns("HOME: Player1, Player2\nAWAY: Player3, Player4")
      RodTheBot::Post.expects(:perform_async).once
      RodTheBot::Post.expects(:perform_in).once

      @game_start_worker.perform(@game_id)
    end
  end
end
