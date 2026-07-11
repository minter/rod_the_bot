require "test_helper"

class RodTheBot::PlayerStreaks::AnalyzerTest < ActiveSupport::TestCase
  test "reports active skater streaks and stops at the first scoreless game" do
    logs = ->(_id, _limit) { [{"points" => 2, "goals" => 1}, {"points" => 1, "goals" => 1}, {"points" => 0, "goals" => 1}] }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 2)

    streaks = analyzer.analyze(player_ids: [42])

    assert_includes streaks, {player_id: "42", streak_type: "Points", length: 2, total_stats: 3}
    assert_includes streaks, {player_id: "42", streak_type: "Goals", length: 3, total_stats: 3}
  end

  test "skips goalie absences without breaking an active win streak" do
    logs = ->(_id, _limit) { [{"decision" => "W"}, {}, {"decision" => "W"}, {"decision" => "L"}, {"decision" => "W"}] }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 2)

    assert_equal [{player_id: "31", streak_type: "Wins", length: 2, total_stats: 2}], analyzer.analyze(player_ids: [31], goalie_ids: [31])
  end

  test "NHL overtime-loss decision code breaks a goalie win streak" do
    logs = ->(_id, _limit) { [{"decision" => "W"}, {"decision" => "O"}, {"decision" => "W"}] }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 1)

    assert_equal [{player_id: "31", streak_type: "Wins", length: 1, total_stats: 1}], analyzer.analyze(player_ids: [31], goalie_ids: [31])
  end

  test "filters mixed season and game-type data" do
    logs = ->(_id, _limit) { [
      {"seasonId" => "20252026", "gameTypeId" => 2, "points" => 1},
      {"seasonId" => "20242025", "gameTypeId" => 2, "points" => 1},
      {"seasonId" => "20252026", "gameTypeId" => 3, "points" => 1}
    ] }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 2)

    assert_empty analyzer.analyze(player_ids: [42])
  end
end
