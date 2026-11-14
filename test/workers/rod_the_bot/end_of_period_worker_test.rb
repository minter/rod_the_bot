require "test_helper"
class RodTheBot::EndOfPeriodWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @end_of_period_worker = RodTheBot::EndOfPeriodWorker.new
    @game_id = "2024020477"
    @original_team_id = ENV["NHL_TEAM_ID"]
    ENV["NHL_TEAM_ID"] = "22"
    Nhl::StatsClient.stubs(:team_situational_records).returns({})
  end

  def teardown
    ENV["NHL_TEAM_ID"] = @original_team_id
  end

  def test_appends_situational_record_after_the_period
    Nhl::StatsClient.stubs(:team_situational_records)
      .with(team_id: 22, season: "20242025", game_type: 2)
      .returns(leading_after_1: {wins: 7, losses: 0, ot_losses: 1})
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_end_of_period_1", allow_playback_repeats: true) do
      feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")
      play = feed["plays"].find { |play| play["eventId"].to_i == 27 }

      @end_of_period_worker.perform(@game_id, play)

      post = RodTheBot::Post.jobs.first["args"].first
      assert post.end_with?("Oilers: 21\n\nThe Oilers are 7-0-1 when leading after one period this season.\n"), post
    end
  end

  def test_posts_period_summary_when_situational_records_fail
    Nhl::StatsClient.stubs(:team_situational_records).raises(Nhl::RequestError, "HTTP 500")
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_end_of_period_1", allow_playback_repeats: true) do
      feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")
      play = feed["plays"].find { |play| play["eventId"].to_i == 27 }

      @end_of_period_worker.perform(@game_id, play)

      assert RodTheBot::Post.jobs.first["args"].first.end_with?("Oilers: 21\n")
    end
  end

  def test_perform
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_end_of_period_1", allow_playback_repeats: true) do
      feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")

      play_id = 27
      play = feed["plays"].find { |play| play["eventId"].to_i == play_id.to_i }

      @end_of_period_worker.perform(@game_id, play)

      assert_equal 1, RodTheBot::Post.jobs.size
      assert_equal 1, RodTheBot::EndOfPeriodStatsWorker.jobs.size
      assert_equal 1, RodTheBot::EndOfPeriodShotChartWorker.jobs.size
      shot_chart_args = RodTheBot::EndOfPeriodShotChartWorker.jobs.first["args"]
      assert_equal [@game_id, 1], shot_chart_args
    end
  end

  def test_format_post
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_end_of_period_1") do
      feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")
      play_id = 27
      play = feed["plays"].find { |play| play["eventId"].to_i == play_id.to_i }

      home = feed.fetch("homeTeam", {})
      away = feed.fetch("awayTeam", {})

      post = @end_of_period_worker.send(:format_post, home, away, play["periodDescriptor"])
      expected_output = <<~POST
        🛑 That's the end of the 1st Period!
        
        Golden Knights - 0 
        Oilers - 4
 
        Shots on goal after the 1st Period:
 
        Golden Knights: 17
        Oilers: 21
      POST
      assert_equal expected_output, post
    end
  end
end
