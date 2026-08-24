require "test_helper"

class Nhl::GameIdTest < ActiveSupport::TestCase
  test "derives season and game type from a game id" do
    game_id = Nhl::GameId.new(2026020018)

    assert_equal "20262027", game_id.season
    assert_equal 2, game_id.game_type
  end

  test "rejects malformed game ids" do
    assert_raises(ArgumentError) { Nhl::GameId.new("bad") }
  end
end
