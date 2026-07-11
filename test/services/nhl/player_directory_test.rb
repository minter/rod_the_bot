require "test_helper"

class Nhl::PlayerDirectoryTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "indexes real game roster identities by player id" do
    VCR.use_cassette("nhl_game_2023020339_gamecenter_pbp") do
      directory = Nhl::PlayerDirectory.for_game(2023020339)
      identity = directory.fetch(8477942)

      assert_equal "Kevin Fiala", identity.full_name
      assert_equal "#22 Kevin Fiala", identity.name_with_number
      assert_equal "LAK", identity.team_abbreviation
    end
  end

  test "caches a game roster for six hours" do
    feed = {
      "homeTeam" => {"id" => 12, "abbrev" => "CAR"},
      "awayTeam" => {"id" => 1, "abbrev" => "NJD"},
      "rosterSpots" => []
    }
    cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stubs(:cache).returns(cache)
    Nhl::GameClient.expects(:play_by_play).once.returns(feed)

    assert_instance_of Nhl::PlayerDirectory, Nhl::PlayerDirectory.for_game(10)
    assert_instance_of Nhl::PlayerDirectory, Nhl::PlayerDirectory.for_game(10)
  end

  test "normalizes string and integer player ids" do
    directory = Nhl::PlayerDirectory.new([
      Nhl::PlayerIdentity.new(id: 42, first_name: "Logan", last_name: "Stankoven", sweater_number: 22)
    ])

    assert_equal "#22 Logan Stankoven", directory.name_with_number("42")
  end

  test "ignores malformed roster entries" do
    directory = Nhl::PlayerDirectory.from_game_feed(
      "homeTeam" => {"id" => 12, "abbrev" => "CAR"},
      "awayTeam" => {"id" => 1, "abbrev" => "NJD"},
      "rosterSpots" => [nil, {}, {"playerId" => 20, "firstName" => {"default" => "Sebastian"}, "lastName" => {"default" => "Aho"}}]
    )

    assert_nil directory.fetch(nil)
    assert_equal "Sebastian Aho", directory.full_name(20)
  end
end
