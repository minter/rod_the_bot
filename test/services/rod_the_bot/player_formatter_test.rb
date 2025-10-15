require "test_helper"

module RodTheBot
  class PlayerFormatterTest < ActiveSupport::TestCase
    include RodTheBot::PlayerFormatter

    test "format_player_from_roster handles string player_id keys" do
      players_hash = {
        "8478550" => {
          number: "86",
          name: "Teuvo Teravainen"
        }
      }

      # Test with integer player_id (common from API)
      result = format_player_from_roster(players_hash, 8478550)
      assert_equal "#86 Teuvo Teravainen", result
    end

    test "format_player_from_roster with string keys and string player_id works" do
      players_hash = {
        "8478550" => {
          number: "86",
          name: "Teuvo Teravainen"
        }
      }

      # Test with string player_id
      result = format_player_from_roster(players_hash, "8478550")
      assert_equal "#86 Teuvo Teravainen", result
    end

    test "format_player_from_roster handles missing player" do
      players_hash = {}

      result = format_player_from_roster(players_hash, 8478550)
      assert_equal "Unknown Player", result
    end

    test "format_player_from_roster handles missing number" do
      players_hash = {
        "8478550" => {
          name: "Teuvo Teravainen"
        }
      }

      result = format_player_from_roster(players_hash, 8478550)
      assert_equal "#? Teuvo Teravainen", result
    end

    test "format_player_from_roster handles missing name" do
      players_hash = {
        "8478550" => {
          number: "86"
        }
      }

      result = format_player_from_roster(players_hash, 8478550)
      assert_equal "#86 Unknown Player", result
    end

    test "format_player_name handles API data structure" do
      player_data = {
        "sweaterNumber" => 86,
        "firstName" => {"default" => "Teuvo"},
        "lastName" => {"default" => "Teravainen"}
      }

      result = format_player_name(player_data)
      assert_equal "#86 Teuvo Teravainen", result
    end

    test "format_player_name handles nil player" do
      result = format_player_name(nil)
      assert_equal "Unknown Player", result
    end

    test "format_player_name handles missing first name" do
      player_data = {
        "sweaterNumber" => 86,
        "lastName" => {"default" => "Teravainen"}
      }

      result = format_player_name(player_data)
      assert_equal "Unknown Player", result
    end

    test "format_player_name handles missing last name" do
      player_data = {
        "sweaterNumber" => 86,
        "firstName" => {"default" => "Teuvo"}
      }

      result = format_player_name(player_data)
      assert_equal "Unknown Player", result
    end

    test "format_player_with_components handles valid data" do
      result = format_player_with_components(86, "Teuvo", "Teravainen")
      assert_equal "#86 Teuvo Teravainen", result
    end

    test "format_player_with_components handles missing number" do
      result = format_player_with_components(nil, "Teuvo", "Teravainen")
      assert_equal "#? Teuvo Teravainen", result
    end

    test "format_player_with_components handles missing first name" do
      result = format_player_with_components(86, nil, "Teravainen")
      assert_equal "Unknown Player", result
    end

    test "format_player_with_components handles missing last name" do
      result = format_player_with_components(86, "Teuvo", nil)
      assert_equal "Unknown Player", result
    end
  end
end

