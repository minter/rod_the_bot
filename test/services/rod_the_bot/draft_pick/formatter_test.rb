require "test_helper"

class RodTheBot::DraftPick::FormatterTest < ActiveSupport::TestCase
  test "formats an unranked selection" do
    pick = {"overallPick" => 31, "round" => 1, "teamName" => {"default" => "Hurricanes"}, "firstName" => {"default" => "Test"}, "lastName" => {"default" => "Player"}, "positionCode" => "C", "countryCode" => "CAN", "height" => 71, "weight" => 180}

    post = RodTheBot::DraftPick::Formatter.new.format(pick, ranking: nil, history: "", year: 2026)

    assert_includes post, "Canadian C Test Player"
    assert_includes post, "Ranking: Unranked"
    assert_includes post, "Height: 5'11\""
  end
end
