require "test_helper"
class RodTheBot::EndOfPeriodWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @end_of_period_worker = RodTheBot::EndOfPeriodWorker.new
    @game_id = "2024020477"
  end

  def test_perform
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_end_of_period_1", allow_playback_repeats: true) do
      feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")

      play_id = 27
      play = feed["plays"].find { |play| play["eventId"].to_i == play_id.to_i }

      @end_of_period_worker.perform(@game_id, play)

      assert_equal 1, RodTheBot::Post.jobs.size
      assert_equal 1, RodTheBot::EndOfPeriodStatsWorker.jobs.size
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
