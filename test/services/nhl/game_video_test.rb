require "test_helper"

class Nhl::GameVideoTest < ActiveSupport::TestCase
  test "normalizes an available game video" do
    Nhl::GameClient.expects(:right_rail).with(2025030134).returns(
      "gameVideo" => {"threeMinRecap" => 6393888986112}
    )
    Nhl::GameClient.expects(:boxscore).with(2025030134).returns(
      "gameDate" => "2026-04-25",
      "awayTeam" => {"abbrev" => "CAR", "placeName" => {"default" => "Carolina"}},
      "homeTeam" => {"abbrev" => "OTT", "placeName" => {"default" => "Ottawa"}}
    )

    video = Nhl::GameVideo.find(2025030134, "threeMinRecap")

    assert_equal 6393888986112, video.id
    assert_equal "threeMinRecap", video.type
    assert_equal "https://www.nhl.com/video/car-at-ott-recap-6393888986112", video.source_url
    assert_equal "Game recap", video.label
    assert_equal "Carolina", video.away_name
    assert_equal "Ottawa", video.home_name
    assert_equal Date.new(2026, 4, 25), video.date
  end

  test "returns nil without fetching the boxscore when the video is unavailable" do
    Nhl::GameClient.expects(:right_rail).returns("gameVideo" => {})
    Nhl::GameClient.expects(:boxscore).never

    assert_nil Nhl::GameVideo.find(2025030134, "condensedGame")
  end

  test "rejects unknown video types before fetching" do
    Nhl::GameClient.expects(:right_rail).never

    assert_raises Nhl::GameVideo::UnknownType do
      Nhl::GameVideo.find(2025030134, "fullGame")
    end
  end

  test "rejects malformed video metadata" do
    Nhl::GameClient.stubs(:right_rail).returns("gameVideo" => {"condensedGame" => 123})
    Nhl::GameClient.stubs(:boxscore).returns(
      "gameDate" => "not-a-date",
      "awayTeam" => {"abbrev" => "CAR"},
      "homeTeam" => {"abbrev" => "OTT"}
    )

    assert_raises Nhl::GameVideo::MalformedVideo do
      Nhl::GameVideo.find(2025030134, "condensedGame")
    end
  end
end
