require "test_helper"

class RodTheBot::YesterdaysScoresWorkerTest < ActiveSupport::TestCase
  def setup
    Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
    @worker = RodTheBot::YesterdaysScoresWorker.new
    Sidekiq::Worker.clear_all  # Clear any previously enqueued jobs
  end

  def test_perform
    Timecop.freeze(Date.new(2023, 11, 29)) do
      VCR.use_cassette("nhl_scores_scoreboard_20231128") do
        NhlApi.expects(:postseason?).returns(false).at_least_once
        @worker.perform
        assert_equal 1, RodTheBot::Post.jobs.size
        expected_output = <<~POST
          🙌 Final scores from last night's games:

          NYI 4 : 5 NJD
          FLA 1 : 2 TOR (SO)
          CAR 4 : 1 PHI
          STL 1 : 3 MIN
          PIT 2 : 3 NSH (OT)
          DAL 2 : 0 WPG
          SEA 3 : 4 CHI
          TBL 1 : 3 ARI
          VGK 4 : 5 EDM (SO)
          ANA 1 : 3 VAN
        POST
        assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
      end
    end
  end

  def test_format_scores_no_games
    Timecop.freeze(Date.new(2023, 11, 24)) do
      VCR.use_cassette("nhl_scores_scoreboard_20231123") do
        scores = NhlApi.fetch_scores
        post = @worker.send(:format_scores, scores)
        expected_post = <<~POST
          🙌 Final scores from last night's games:

          No games scheduled
        POST
        assert_equal expected_post, post
      end
    end
  end

  def test_perform_with_postponed_game
    NhlApi.stubs(:postseason?).returns(false)

    Timecop.freeze(Date.new(2024, 10, 13)) do
      VCR.use_cassette("nhl_scores_scoreboard_20241012") do
        @worker.perform
        assert_equal 1, RodTheBot::Post.jobs.size
        expected_output = <<~POST
          🙌 Final scores from last night's games:

          LAK 1 : 2 BOS (OT)
          FLA 2 : 5 BUF
          PIT 2 : 4 TOR
          OTT 1 : 4 MTL
          NSH 0 : 3 DET
          CAR @ TBL - Postponed
          UTA 6 : 5 NYR (OT)
          NJD 5 : 3 WSH
          NYI 0 : 3 DAL
          SEA 5 : 4 MIN (SO)
          CBJ 6 : 4 COL
          PHI 3 : 6 CGY
          CHI 5 : 2 EDM
          ANA 2 : 0 SJS
        POST
        assert_equal expected_output, RodTheBot::Post.jobs.first["args"].first
      end
    end
  end

  def teardown
    Sidekiq::Worker.clear_all  # Clear enqueued jobs after each test
  end
end
