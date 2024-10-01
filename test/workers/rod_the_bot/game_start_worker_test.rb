require "test_helper"

class RodTheBot::GameStartWorkerTest < ActiveSupport::TestCase
  def setup
    @game_start_worker = RodTheBot::GameStartWorker.new
    @game_id = "2023030246"
  end

  test "find_starting_goalie" do
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_game_start") do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      @game_start_worker.instance_variable_set(:@feed, feed)
      goalie = @game_start_worker.send(:find_starting_goalie, "homeTeam")

      assert_not_nil goalie
      assert_equal "S. Skinner", goalie["name"]["default"]
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

  test "format_post" do
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_game_start") do
      feed = NhlApi.fetch_pbp_feed(@game_id)
      officials = {referees: ["Garrett Rank", "Jean Hebert"], linesmen: ["Shandor Alphonso", "Jonny Murray"]}
      home_goalie = {"sweaterNumber" => "74", "name" => {"default" => "S. Skinner"}}
      away_goalie = {"sweaterNumber" => "31", "name" => {"default" => "A. Silovs"}}
      home_goalie_record = "(5-3-0, 3.22 GAA, 0.877 SV%)"
      away_goalie_record = "(5-3-0, 2.62 GAA, 0.907 SV%)"

      post = @game_start_worker.send(:format_post, feed, officials, home_goalie, home_goalie_record, away_goalie, away_goalie_record)

      assert_match(/🚦 It's puck drop at .+ for .+ at .+!/, post)
      assert_match(/Starting Goalies:/, post)
      assert_match(/EDM: #74 S. Skinner \(5-3-0, 3.22 GAA, 0.877 SV%\)/, post)
      assert_match(/VAN: #31 A. Silovs \(5-3-0, 2.62 GAA, 0.907 SV%\)/, post)
      assert_match(/Referees: Garrett Rank, Jean Hebert/, post)
      assert_match(/Lines: Shandor Alphonso, Jonny Murray/, post)
    end
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
        "homeTeam" => {"name" => {"default" => "Home Team"}, "abbrev" => "HOME"},
        "awayTeam" => {"name" => {"default" => "Away Team"}, "abbrev" => "AWAY"}
      })
      NhlApi.expects(:officials).returns({referees: ["Ref1", "Ref2"], linesmen: ["Lines1", "Lines2"]})
      NhlApi.expects(:fetch_player_landing_feed).twice.returns({
        "featuredStats" => {
          "regularSeason" => {
            "subSeason" => {"wins" => 10, "losses" => 5, "otLosses" => 2, "goalsAgainstAvg" => 2.5, "savePctg" => 0.915}
          }
        }
      })
      RodTheBot::Post.expects(:perform_async).once

      @game_start_worker.perform(@game_id)
    end
  end
end
