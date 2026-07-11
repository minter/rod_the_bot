require "test_helper"

class Nhl::GameClientTest < ActiveSupport::TestCase
  test "finds a play regardless of id representation" do
    Nhl::GameClient.stubs(:play_by_play).with(10).returns(
      "plays" => [{"eventId" => 20}, {"eventId" => 21}]
    )

    assert_equal({"eventId" => 21}, Nhl::GameClient.play(10, "21"))
  end

  test "returns nil when the feed has no plays" do
    Nhl::GameClient.stubs(:play_by_play).returns({})

    assert_nil Nhl::GameClient.play(10, 20)
  end
end
