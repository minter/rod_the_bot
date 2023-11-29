require "test_helper"
require "vcr"

class ThreeStarsWorkerTest < ActiveSupport::TestCase
  def setup
    @worker = RodTheBot::ThreeStarsWorker.new
    VCR.configure do |config|
      config.cassette_library_dir = "fixtures/vcr_cassettes"
      config.hook_into :webmock
    end
  end

  def test_perform
    VCR.use_cassette("nhl_game_landing_2023020328") do
      @worker.perform(2023020328)
      assert_not_empty @worker.feed
    end
  end

  def test_format_three_stars
    VCR.use_cassette("nhl_game_landing_2023020328") do
      @worker.perform(2023020328)
      three_stars = @worker.feed["summary"]["threeStars"]
      post = @worker.send(:format_three_stars, three_stars)
      expected_output = <<~POST
        Three Stars Of The Game:
        
        ⭐️⭐️⭐️ PHI #11 Travis Konecny (1G, 1PT)
        
        ⭐️⭐️ CAR #58 Michael Bunting (1G, 1A, 2PTS)
        
        ⭐️ CAR #52 Pyotr Kochetkov (1.0 GAA, 0.966 SV%)
        
      POST
      assert_equal expected_output, post
    end
  end
end
