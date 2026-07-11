require "test_helper"

class RodTheBot::Penalty::PostBuilderTest < ActiveSupport::TestCase
  setup do
    @players = Nhl::PlayerDirectory.new([
      Nhl::PlayerIdentity.new(id: 1, first_name: "Seth", last_name: "Jarvis", sweater_number: 24, team_id: 12),
      Nhl::PlayerIdentity.new(id: 2, first_name: "Jordan", last_name: "Staal", sweater_number: 11, team_id: 12)
    ])
    @teams = [{"commonName" => {"default" => "Hurricanes"}}, {"commonName" => {"default" => "Rangers"}}]
    @builder = RodTheBot::Penalty::PostBuilder.new
  end

  test "formats a standard penalty and alternate server" do
    post = @builder.build(play: play("MIN", "cross-checking", served: 2), players: @players, your_team: @teams[0], their_team: @teams[1], tracked_team_id: 12)

    assert_includes post, "🙃 Hurricanes Penalty"
    assert_includes post, "#24 Seth Jarvis - Cross-Checking"
    assert_includes post, "2 minute Minor penalty at 12:34 of the 2nd Period"
    assert_includes post, "Penalty served by #11 Jordan Staal"
  end

  test "formats a penalty shot" do
    post = @builder.build(play: play("PS", "ps-hooking-on-breakaway"), players: @players, your_team: @teams[0], their_team: @teams[1], tracked_team_id: 12)

    assert_includes post, "#24 Seth Jarvis - Hooking on Breakaway"
    assert_includes post, "penalty shot awarded"
  end

  private

  def play(type, description, served: nil)
    {"details" => {"typeCode" => type, "descKey" => description, "duration" => 2, "committedByPlayerId" => 1, "servedByPlayerId" => served}, "periodDescriptor" => {"number" => 2}, "timeInPeriod" => "12:34"}
  end
end
