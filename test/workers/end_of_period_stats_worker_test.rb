require "minitest/autorun"
require "vcr"

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
end

class EndOfPeriodStatsWorkerTest < Minitest::Test
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EndOfPeriodStatsWorker.new
    @game_id = 2023020339
    ENV["NHL_TEAM_ID"] = "26"
  end

  def test_perform
    VCR.use_cassette("nhl_gamecenter") do
      period_number = 1 # replace with a real period number

      @worker.perform(@game_id, period_number)
      assert_equal 2, RodTheBot::Post.jobs.size
      toi_expected_output = <<~POST
        ⏱️ Time on ice leaders for the Kings after the 1 period
        
        D. Doughty - 07:28
        V. Gavrikov - 06:56
        A. Kopitar - 06:26
        M. Anderson - 06:19
        K. Fiala - 06:19
      POST

      sog_expected_output = <<~POST
        🏒 Shots on goal leaders for the Kings after the 1 period
        
        Q. Byfield - 3
        K. Fiala - 3
        A. Kaliyev - 1
        M. Anderson - 1
        D. Doughty - 1
      POST

      assert_equal toi_expected_output, RodTheBot::Post.jobs.first["args"].first
      assert_equal sog_expected_output, RodTheBot::Post.jobs.second["args"].first
    end
  end
end
