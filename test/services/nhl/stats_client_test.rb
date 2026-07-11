require "test_helper"

class Nhl::StatsClientTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "indexes teams by numeric id" do
    Nhl::StatsClient.expects(:get_json).with("/team").returns("data" => [{"id" => 12, "fullName" => "Carolina Hurricanes"}])

    assert_equal "Carolina Hurricanes", Nhl::StatsClient.teams.dig(12, :fullName)
  end

  test "returns empty milestone data when the API is unavailable" do
    Nhl::StatsClient.stubs(:get_json).raises(Nhl::RequestError, "unavailable")

    assert_equal({}, Nhl::StatsClient.skater_milestones)
  end
end
