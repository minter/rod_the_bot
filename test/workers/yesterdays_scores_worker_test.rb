require "test_helper"
require "minitest/autorun"

class YesterdaysScoresWorkerTest < ActiveSupport::TestCase
  def setup
    Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
    @worker = RodTheBot::YesterdaysScoresWorker.new

    VCR.configure do |config|
      config.cassette_library_dir = "fixtures/vcr_cassettes"
      config.hook_into :webmock
      config.allow_http_connections_when_no_cassette = false
    end
  end

  def test_perform
    Timecop.freeze(Date.new(2023, 11, 29)) do
      @worker.stub :postseason?, false do
        VCR.use_cassette("nhl_scores_scoreboard_20231128") do
          @worker.perform
          assert_not_nil @worker.send(:fetch_yesterdays_scores)
        end
      end
    end
  end

  def test_format_scores
    Timecop.freeze(Date.new(2023, 11, 29)) do
      @worker.stub :postseason?, false do
        VCR.use_cassette("nhl_scores_scoreboard_20231128") do
          @worker.perform
          scores = @worker.send(:fetch_yesterdays_scores)
          post = @worker.send(:format_scores, scores)
          expected_post = <<~POST
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
          assert_equal expected_post, post
        end
      end
    end
  end

  def test_format_scores_no_games
    Timecop.freeze(Date.new(2023, 11, 24)) do
      VCR.use_cassette("nhl_scores_scoreboard_20231123") do
        @worker.perform
        scores = @worker.send(:fetch_yesterdays_scores)
        post = @worker.send(:format_scores, scores)
        expected_post = <<~POST
          🙌 Final scores from last night's games:

          No games scheduled
        POST
        assert_equal expected_post, post
      end
    end
  end
end
