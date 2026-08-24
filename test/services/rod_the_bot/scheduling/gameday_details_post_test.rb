require "test_helper"

class RodTheBot::Scheduling::GamedayDetailsPostTest < ActiveSupport::TestCase
  test "combines available series context with compact manual links" do
    details = RodTheBot::Scheduling::GamedayDetailsPost.new.build(
      series: {
        tracked_abbrev: "CAR", opponent_abbrev: "FLA", tracked_wins: 1, opponent_wins: 1,
        completed_meetings: 2, total_meetings: 3,
        last_meeting: {
          date: "2027-01-21", away_abbrev: "FLA", away_score: 2,
          home_abbrev: "CAR", home_score: 5, last_period_type: "REG", overtime_periods: nil
        }
      },
      radio_url: "https://media.example/CAR-radio.m3u8",
      tickets_url: "https://tickets.example/long-tracking-url"
    )

    assert_equal <<~POST, details[:text]
      Season series: tied 1-1 (meeting 3 of 3).
      Last: FLA 2, CAR 5 — Jan 21.
      🎧 Listen live · 🎟️ Tickets
    POST
    assert_equal [
      {"text" => "Listen live", "url" => "https://media.example/CAR-radio.m3u8"},
      {"text" => "Tickets", "url" => "https://tickets.example/long-tracking-url"}
    ], details[:links]
  end

  test "omits series lines until completed-game data is available" do
    details = RodTheBot::Scheduling::GamedayDetailsPost.new.build(
      series: nil,
      radio_url: "https://media.example/CAR-radio.m3u8",
      tickets_url: nil
    )

    assert_equal "🎧 Listen live\n", details[:text]
  end

  test "returns nil when no optional details are available" do
    assert_nil RodTheBot::Scheduling::GamedayDetailsPost.new.build(
      series: nil, radio_url: nil, tickets_url: nil
    )
  end

  test "fits within the Bluesky grapheme limit with links and team hashtags" do
    details = RodTheBot::Scheduling::GamedayDetailsPost.new.build(
      series: {
        tracked_abbrev: "CAR", opponent_abbrev: "WSH", tracked_wins: 3, opponent_wins: 0,
        completed_meetings: 3, total_meetings: 4,
        last_meeting: {
          date: "2027-04-30", away_abbrev: "CAR", away_score: 10,
          home_abbrev: "WSH", home_score: 11, last_period_type: "OT", overtime_periods: 4
        }
      },
      radio_url: "https://media.example/very/long/radio/url/index.m3u8",
      tickets_url: "https://tickets.example/very/long/url?utm_source=nhl&utm_campaign=gameday"
    )

    final_text = "#{details[:text]}\n#CarolinaCulture"
    grapheme_count = final_text.scan(/\X/).length

    assert_operator grapheme_count, :<=, 300, "Post exceeds Bluesky's 300-grapheme limit: #{grapheme_count}"
    details[:links].each { |link| refute_includes final_text, link["url"] }
  end
end
