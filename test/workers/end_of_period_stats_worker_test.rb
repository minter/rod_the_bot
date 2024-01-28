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
    @game_id = 2023020773
    ENV["NHL_TEAM_ID"] = "19"
  end

  def test_perform
    VCR.use_cassette("nhl_gamecenter_2023020773_landing") do
      period_number = "2nd"

      @worker.perform(@game_id, period_number)
      assert_equal 3, RodTheBot::Post.jobs.size
      toi_expected_output = <<~POST
        ⏱️ Time on ice leaders for the Blues after the 2nd period
        
        N. Leddy - 14:48
        R. Thomas - 14:15
        C. Parayko - 13:58
        J. Kyrou - 13:27
        T. Krug - 13:18
      POST

      sog_expected_output = <<~POST
        🏒 Shots on goal leaders for the Blues after the 2nd period
        
        P. Buchnevich - 4
        N. Leddy - 3
        T. Krug - 2
        J. Neighbours - 2
        J. Kyrou - 2
      POST

      game_stats_expected_output = <<~POST
        📄 Game comparison after the 2nd period
        
        Faceoffs: LAK - 47.4% | STL - 52.6%
        PIMs: LAK - 8 | STL - 2
        Blocks: LAK - 9 | STL - 5
        Hits: LAK - 14 | STL - 17
        Power Play: LAK - 0/1 | STL - 1/4
        Giveaways: LAK - 2 | STL - 2
        Takeaways: LAK - 8 | STL - 4
      POST

      assert_equal toi_expected_output, RodTheBot::Post.jobs.second["args"].first
      assert_equal sog_expected_output, RodTheBot::Post.jobs.third["args"].first
      assert_equal game_stats_expected_output, RodTheBot::Post.jobs.first["args"].first
    end
  end
end
