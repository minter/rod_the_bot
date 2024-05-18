require "test_helper"
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
end

class EndOfPeriodWorkerTest < Minitest::Test
  def setup
    Sidekiq::Worker.clear_all
    @end_of_period_worker = RodTheBot::EndOfPeriodWorker.new
    @game_id = "2023020339"
  end

  def test_perform
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_end_of_period_1", allow_playback_repeats: true) do
      feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")

      play_id = 28
      play = feed["plays"].find { |play| play["eventId"].to_i == play_id.to_i }

      @end_of_period_worker.perform(@game_id, play)

      assert_equal 1, RodTheBot::Post.jobs.size
      assert_equal 1, RodTheBot::EndOfPeriodStatsWorker.jobs.size
    end
  end

  def test_format_post
    VCR.use_cassette("nhl_game_#{@game_id}_gamecenter_pbp_end_of_period_1") do
      feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")
      play_id = 28
      play = feed["plays"].find { |play| play["eventId"].to_i == play_id.to_i }

      home = feed.fetch("homeTeam", {})
      away = feed.fetch("awayTeam", {})

      post = @end_of_period_worker.send(:format_post, home, away, play["periodDescriptor"])
      expected_output = <<~POST
        🛑 That's the end of the 1st Period!
        
        Capitals - 1 
        Kings - 1
        
        Shots on goal after the 1st Period:
        
        Capitals: 5
        Kings: 11
      POST
      assert_equal expected_output, post
    end
  end
end
