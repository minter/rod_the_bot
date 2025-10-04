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

        ⭐️⭐️⭐️ CAR #28 W. Carrier (1G, 1A, 2PTS)

        ⭐️⭐️ CAR #24 S. Jarvis (2G, 2PTS)

        ⭐️ CAR #26 S. Walker (1G, 2A, 3PTS)
      POST
      assert_equal expected_output, post
    end
  end

  def test_format_three_stars_with_new_api_format
    # Test with mock data matching the new NHL API format (name field instead of firstName/lastName)
    three_stars = [
      {
        "star" => 1,
        "playerId" => 8483465,
        "teamAbbrev" => "NSH",
        "name" => {
          "default" => "J. Kemell"
        },
        "sweaterNo" => 25,
        "position" => "R",
        "goals" => 1,
        "assists" => 1,
        "points" => 2
      },
      {
        "star" => 2,
        "playerId" => 8479370,
        "teamAbbrev" => "NSH",
        "name" => {
          "default" => "T. Jost"
        },
        "sweaterNo" => 17,
        "position" => "C",
        "goals" => 1,
        "assists" => 0,
        "points" => 1
      },
      {
        "star" => 3,
        "playerId" => 8477424,
        "teamAbbrev" => "NSH",
        "name" => {
          "default" => "J. Saros"
        },
        "sweaterNo" => 74,
        "position" => "G",
        "goalsAgainstAverage" => 1.88,
        "savePctg" => 0.92
      }
    ]

    post = @worker.send(:format_three_stars, three_stars)
    expected_output = <<~POST
      Three Stars Of The Game:

      ⭐️⭐️⭐️ NSH #74 J. Saros (1.88 GAA, 0.920 SV%)

      ⭐️⭐️ NSH #17 T. Jost (1G, 1PT)

      ⭐️ NSH #25 J. Kemell (1G, 1A, 2PTS)
    POST
    assert_equal expected_output, post
  end
end
