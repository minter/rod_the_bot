require "test_helper"

class RodTheBot::ThreeStarsWorkerTest < ActiveSupport::TestCase
  def setup
    @worker = RodTheBot::ThreeStarsWorker.new
    VCR.configure do |config|
      config.cassette_library_dir = "fixtures/vcr_cassettes"
      config.hook_into :webmock
    end
  end

  def test_perform
    VCR.use_cassette("nhl_game_landing_2023020763") do
      @worker.perform(2023020763)
      assert_not_empty @worker.feed
    end
  end

  def test_format_three_stars
    VCR.use_cassette("nhl_game_landing_2024010043") do
      @worker.perform(2024010043)
      three_stars = @worker.feed["summary"]["threeStars"]
      post = @worker.send(:format_three_stars, three_stars)
      expected_output = <<~POST
        Three Stars Of The Game:
        
        ⭐️⭐️⭐️ CAR #28 Unknown Player (1G, 1A, 2PTS)
        
        ⭐️⭐️ CAR #24 Unknown Player (2G, 2PTS)
        
        ⭐️ CAR #26 Unknown Player (1G, 2A, 3PTS)

      POST
      assert_equal expected_output, post
    end
  end
end
