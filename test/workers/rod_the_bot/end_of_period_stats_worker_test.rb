require "test_helper"

class RodTheBot::EndOfPeriodStatsWorkerTest < ActiveSupport::TestCase
  def setup
    Sidekiq::Worker.clear_all
    @worker = RodTheBot::EndOfPeriodStatsWorker.new
    @game_id = 2024020477
    ENV["NHL_TEAM_ID"] = "22"
  end

  def test_perform
    VCR.use_cassette("nhl_gamecenter_2024020477_landing") do
      period_number = "1st"

      @worker.perform(@game_id, period_number)
      assert_equal 3, RodTheBot::Post.jobs.size
      toi_expected_output = <<~POST
        ⏱️ Time on ice leaders for the Oilers after the 1st Period
        
        L. Draisaitl - 7:45
        B. Kulak - 7:28
        E. Bouchard - 7:20
        D. Nurse - 6:59
        C. McDavid - 6:05
      POST

      sog_expected_output = <<~POST
        🏒 Shots on goal leaders for the Oilers after the 1st Period
        
        E. Bouchard - 3
        V. Podkolzin - 2
        M. Ekholm - 2
        R. Nugent-Hopkins - 1
        L. Draisaitl - 1
      POST

      game_stats_expected_output = <<~POST
        📄 Game comparison after the 1st Period
        
        Faceoffs: VGK - 42.9% | EDM - 57.1%
        PIMs: VGK - 2 | EDM - 2
        Blocks: VGK - 3 | EDM - 11
        Hits: VGK - 11 | EDM - 6
        Power Play: VGK - 0/1 | EDM - 1/1
        Giveaways: VGK - 5 | EDM - 4
        Takeaways: VGK - 0 | EDM - 1
      POST

      assert_equal toi_expected_output, RodTheBot::Post.jobs.first["args"].first
      assert_equal sog_expected_output, RodTheBot::Post.jobs.second["args"].first
      assert_equal game_stats_expected_output, RodTheBot::Post.jobs.third["args"].first
    end
  end
end
