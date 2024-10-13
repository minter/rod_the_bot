require "test_helper"

class RodTheBot::EndOfPeriodStatsWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EndOfPeriodStatsWorker.new
    @game_id = 2024020038
    ENV["NHL_TEAM_ID"] = "52"
  end

  def test_perform
    VCR.use_cassette("nhl_gamecenter_2024020038_landing") do
      period_number = "1st"

      @worker.perform(@game_id, period_number)
      assert_equal 3, RodTheBot::Post.jobs.size
      toi_expected_output = <<~POST
        ⏱️ Time on ice leaders for the Jets after the 1st Period
        
        J. Morrissey - 7:48
        N. Pionk - 7:27
        D. Samberg - 7:19
        D. DeMelo - 7:18
        M. Scheifele - 6:20
      POST

      sog_expected_output = <<~POST
        🏒 Shots on goal leaders for the Jets after the 1st Period
        
        V. Namestnikov - 1
        R. Kupari - 1
        N. Pionk - 1
        N. Ehlers - 1
        M. Scheifele - 1
      POST

      game_stats_expected_output = <<~POST
        📄 Game comparison after the 1st Period
        
        Faceoffs: MIN - 42.1% | WPG - 57.9%
        PIMs: MIN - 2 | WPG - 2
        Blocks: MIN - 4 | WPG - 3
        Hits: MIN - 7 | WPG - 7
        Power Play: MIN - 0/1 | WPG - 0/1
        Giveaways: MIN - 3 | WPG - 7
        Takeaways: MIN - 3 | WPG - 2
      POST

      assert_equal toi_expected_output, RodTheBot::Post.jobs.second["args"].first
      assert_equal sog_expected_output, RodTheBot::Post.jobs.third["args"].first
      assert_equal game_stats_expected_output, RodTheBot::Post.jobs.first["args"].first
    end
  end
end
