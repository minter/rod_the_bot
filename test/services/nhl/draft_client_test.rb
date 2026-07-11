require "test_helper"

class Nhl::DraftClientTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "combines the four ranking groups" do
    Nhl::DraftClient.stubs(:ranking_group).returns([{"rank" => 1}])

    rankings = Nhl::DraftClient.rankings(2026)

    assert_equal %i[north_american_skaters international_skaters north_american_goalies international_goalies], rankings.keys
  end
end
