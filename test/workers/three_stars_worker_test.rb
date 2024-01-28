require "test_helper"

class ThreeStarsWorkerTest < ActiveSupport::TestCase
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
    VCR.use_cassette("nhl_game_landing_2023020763") do
      @worker.perform(2023020763)
      three_stars = @worker.feed["summary"]["threeStars"]
      post = @worker.send(:format_three_stars, three_stars)
      expected_output = <<~POST
        Three Stars Of The Game:
        
        ⭐️⭐️⭐️ CAR #88 Martin Necas (1G, 1PT)
        
        ⭐️⭐️ CAR #74 Jaccob Slavin 
        
        ⭐️ CAR #7 Dmitry Orlov (1G, 1PT)

      POST
      assert_equal expected_output, post
    end
  end
end
