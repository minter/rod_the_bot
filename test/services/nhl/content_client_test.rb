require "test_helper"

class Nhl::ContentClientTest < ActiveSupport::TestCase
  setup { Rails.cache.clear }

  test "fetches player content by player tag" do
    Nhl::ContentClient.expects(:get_json).with("/players?tags.slug=playerid-42").returns("data" => [])

    assert_equal({"data" => []}, Nhl::ContentClient.player(42))
  end
end
