require "test_helper"

class RodTheBot::EdgeRecap::GameDataTest < ActiveSupport::TestCase
  GAME = 2026020321
  OTHER = 2026020309

  test "returns nil when the team list lacks the game" do
    assert_nil build(team: distance_payload(game(OTHER, 45.0)))
    assert_nil build(team: nil)
  end

  test "ranks the game among recent games" do
    result = build(team: distance_payload(game(GAME, 45.0), game(OTHER, 47.0), game(2026020271, 44.0)))

    assert_equal 45.0, result.distance
    assert_equal 2, result.rank
    assert_equal 3, result.games
  end

  test "uses the entry with the matching game id when the same opponent appears twice" do
    result = build(team: distance_payload(game(OTHER, 45.9), game(GAME, 45.3)))

    assert_equal 45.3, result.distance
  end

  test "reports situational splits and omits a situation with no ice time" do
    entry = game(GAME, 45.0, even: [39.5, 3000], power_play: [0.0, 0], penalty_kill: [2.2, 240])
    result = build(team: distance_payload(entry))

    assert_equal 39.5, result.even
    assert_nil result.power_play
    assert_equal 2.2, result.penalty_kill
  end

  test "reports the opponent distance only from the same game" do
    team = distance_payload(game(GAME, 45.0))

    assert_equal 44.9, build(team: team, opponent: distance_payload(game(GAME, 44.9))).opponent_distance
    assert_nil build(team: team, opponent: distance_payload(game(OTHER, 46.0))).opponent_distance
    assert_nil build(team: team, opponent: nil).opponent_distance
  end

  test "orders skaters by distance and drops those without the game" do
    skaters = {
      1 => distance_payload(game(GAME, 2.5, seconds: 1000)),
      2 => distance_payload(game(OTHER, 3.3), game(GAME, 3.1, seconds: 1301)),
      3 => distance_payload(game(OTHER, 2.9)),
      4 => nil
    }
    result = build(team: distance_payload(game(GAME, 45.0)), skaters: skaters)

    assert_equal [2, 1], result.skaters.map(&:player_id)
    assert_equal 3.1, result.skaters.first.miles
    assert_equal 1301, result.skaters.first.seconds
  end

  test "collects season marks from this game with their list rank" do
    shots = {"hardestShots" => [shot(OTHER, 10, 97.5), shot(GAME, 11, 92.0), shot(OTHER, 12, 91.6), shot(GAME, 13, 91.3)]}
    speeds = {"topSkatingSpeeds" => [speed(OTHER, 20, 23.5), speed(GAME, 21, 22.4)]}
    result = build(team: distance_payload(game(GAME, 45.0)), shots: shots, speeds: speeds)

    assert_equal [[:shot, 11, 92.0, 2], [:shot, 13, 91.3, 4], [:speed, 21, 22.4, 2]],
      result.marks.map { |mark| [mark.kind, mark.player_id, mark.mph, mark.rank] }
  end

  test "has no marks when shot and speed payloads are missing" do
    assert_equal [], build(team: distance_payload(game(GAME, 45.0))).marks
  end

  private

  def build(team:, opponent: nil, shots: nil, speeds: nil, skaters: {})
    RodTheBot::EdgeRecap::GameData.build(game_id: GAME, team: team, opponent: opponent, shots: shots, speeds: speeds, skaters: skaters)
  end

  def distance_payload(*games)
    {"skatingDistanceLast10" => games}
  end

  def link(game_id)
    "/gamecenter/sea-vs-car/2026/11/14/#{game_id}"
  end

  def game(game_id, miles, seconds: 17_800, even: nil, power_play: nil, penalty_kill: nil)
    entry = {"gameCenterLink" => link(game_id), "distanceSkatedAll" => {"imperial" => miles}, "toiAll" => seconds}
    {"Even" => even, "PP" => power_play, "PK" => penalty_kill}.each do |suffix, (split_miles, split_seconds)|
      next unless split_miles

      entry["distanceSkated#{suffix}"] = {"imperial" => split_miles}
      entry["toi#{suffix}"] = split_seconds
    end
    entry
  end

  def shot(game_id, player_id, mph)
    {"gameCenterLink" => link(game_id), "player" => {"id" => player_id}, "shotSpeed" => {"imperial" => mph}}
  end

  def speed(game_id, player_id, mph)
    {"gameCenterLink" => link(game_id), "player" => {"id" => player_id}, "skatingSpeed" => {"imperial" => mph}}
  end
end
