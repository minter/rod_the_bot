require "test_helper"

class RodTheBot::Goal::PostBuilderTest < ActiveSupport::TestCase
  test "formats a recorded power-play goal" do
    VCR.use_cassette("nhl_game_2023020702_goal_play_390", allow_playback_repeats: true) do
      feed = Nhl::GameClient.play_by_play("2023020702")
      play = feed.fetch("plays").find { |candidate| candidate["eventId"] == 390 }
      players = Nhl::GameInfo.roster_from_feed(feed)

      result = RodTheBot::Goal::PostBuilder.new(team_id: 12).build(play: play, feed: feed, players: players)

      assert_includes result.post, "Red Wings Power Play Goal"
      assert_includes result.post, "#37 J.T. Compher"
      refute result.penalty_shot
    end
  end
end
