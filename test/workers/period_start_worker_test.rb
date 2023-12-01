require "minitest/autorun"
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
end

class PeriodStartWorkerTest < Minitest::Test
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::PeriodStartWorker.new
    @game_id = 2023020341 # replace with a real game id
  end

  def test_perform_first_period
    VCR.use_cassette("nhl_gamecenter_pbp_#{@game_id}") do
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")

      play_id = 102
      play = @feed["plays"].find { |play| play["eventId"].to_i == play_id.to_i }

      @worker.perform(@game_id, play)

      expected_output = <<~POST
        🎬 It's time to start the 1st period at PNC Arena!
        
        We're ready for another puck drop between the Islanders and the Hurricanes!
      POST
      assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
      # Add assertions here based on what you expect to happen when perform is called
    end
  end

  def test_perform_ot_period
    VCR.use_cassette("nhl_gamecenter_pbp_#{@game_id}") do
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/play-by-play")

      play_id = 449
      play = @feed["plays"].find { |play| play["eventId"].to_i == play_id.to_i }

      @worker.perform(@game_id, play)

      expected_output = <<~POST
        🎬 It's time to start the OT period at PNC Arena!
        
        We're ready for another puck drop between the Islanders and the Hurricanes!
      POST

      assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
    end
  end
end
