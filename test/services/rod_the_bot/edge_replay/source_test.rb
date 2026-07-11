require "test_helper"

class RodTheBot::EdgeReplay::SourceTest < ActiveSupport::TestCase
  test "rejects malformed game ids without making a request" do
    source = RodTheBot::EdgeReplay::Source.new
    Net::HTTP.expects(:new).never

    assert_nil source.edge_json("bad", 1, Rails.root.join("tmp"))
  end

  test "returns only landing feeds with both teams" do
    Nhl::GameClient.stubs(:landing).returns("homeTeam" => {"id" => 1})

    assert_nil RodTheBot::EdgeReplay::Source.new.game_data(10)
  end
end
