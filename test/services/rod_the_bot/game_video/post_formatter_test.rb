require "test_helper"

class RodTheBot::GameVideo::PostFormatterTest < ActiveSupport::TestCase
  test "formats normalized game video metadata" do
    video = Nhl::GameVideo::Video.new(
      id: 123,
      type: "condensedGame",
      source_url: "https://www.nhl.com/video/example",
      label: "Condensed game",
      away_name: "Carolina",
      home_name: "Ottawa",
      date: Date.new(2026, 4, 25)
    )

    assert_equal(
      "🎥 Condensed game: Carolina at Ottawa on April 25, 2026.",
      RodTheBot::GameVideo::PostFormatter.new.format(video)
    )
  end
end
