require "test_helper"

class RodTheBot::ScoringChange::FormatterTest < ActiveSupport::TestCase
  test "formats a corrected goal from a recorded NHL feed" do
    VCR.use_cassette("nhl_game_2024010043_format_post") do
      feed = Nhl::GameClient.play_by_play("2024010043")
      play = feed.fetch("plays").find { |candidate| candidate["typeDescKey"] == "goal" }
      players = Nhl::PlayerDirectory.from_game_feed(feed)

      post = RodTheBot::ScoringChange::Formatter.new.correction(play: play, scoring_team: feed["homeTeam"], players: players)

      assert_includes post, "🔔 Scoring Change"
      assert_includes post, "🚨"
    end
  end
end
