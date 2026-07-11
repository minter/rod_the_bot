require "test_helper"

class Nhl::PlayerIdentityTest < ActiveSupport::TestCase
  test "normalizes a game roster player and exposes consistent formats" do
    identity = Nhl::PlayerIdentity.from_game_roster(
      {
        "playerId" => 8482113,
        "firstName" => {"default" => "Logan"},
        "lastName" => {"default" => "Stankoven"},
        "sweaterNumber" => 22,
        "teamId" => 12,
        "positionCode" => "C"
      },
      team_abbreviation: "CAR"
    )

    assert_equal "Logan Stankoven", identity.full_name
    assert_equal "#22 Logan Stankoven", identity.name_with_number
    assert_equal "L. Stankoven", identity.abbreviated_name
    assert_equal "CAR", identity.team_abbreviation
  end

  test "uses an explicit placeholder when the roster omits a number" do
    identity = Nhl::PlayerIdentity.new(id: 1, first_name: "Logan", last_name: "Stankoven")

    assert_equal "#? Logan Stankoven", identity.name_with_number
  end
end
