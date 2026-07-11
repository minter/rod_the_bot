require "test_helper"

class RodTheBot::ScoringChange::DetectorTest < ActiveSupport::TestCase
  test "detects a correction using a recorded NHL play-by-play response" do
    VCR.use_cassette("nhl_game_2024010043_scoring_change") do
      feed = Nhl::GameClient.play_by_play("2024010043")
      play = feed.fetch("plays").find { |candidate| candidate["typeDescKey"] == "goal" }
      original = play.deep_dup
      original["details"]["assist1PlayerId"] = 8_000_000

      result = RodTheBot::ScoringChange::Detector.new(feed).detect(play_id: play["eventId"], original_play: original)

      assert_equal :corrected, result.status
      assert_equal play["eventId"], result.play["eventId"]
    end
  end

  test "finds the recorded challenge for a removed goal" do
    original = {"timeInPeriod" => "12:17", "periodDescriptor" => {"number" => 2}, "details" => {}}
    VCR.use_cassette("nhl_game_2025010061_overturned_goal") do
      feed = Nhl::GameClient.play_by_play("2025010061")
      result = RodTheBot::ScoringChange::Detector.new(feed).detect(play_id: 687, original_play: original)

      assert_equal :overturned, result.status
      assert_includes result.challenge.dig("details", "reason"), "chlg"
    end
  end
end
