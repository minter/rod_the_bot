require "test_helper"

class RodTheBot::PlayerStreaks::AnalyzerTest < ActiveSupport::TestCase
  test "reports active skater streaks and stops at the first scoreless game" do
    logs = ->(_id) { [{"points" => 2, "goals" => 1}, {"points" => 1, "goals" => 1}, {"points" => 0, "goals" => 1}] }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 2)

    streaks = analyzer.analyze(player_ids: [42])

    assert_includes streaks, {player_id: "42", streak_type: "Points", length: 2, total_stats: 3}
    assert_includes streaks, {player_id: "42", streak_type: "Goals", length: 3, total_stats: 3}
  end

  test "counts streaks longer than ten games" do
    logs = ->(_id) { Array.new(14) { {"points" => 1, "goals" => 0} } + [{"points" => 0}] }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 3)

    assert_equal [{player_id: "42", streak_type: "Points", length: 14, total_stats: 14}], analyzer.analyze(player_ids: [42])
  end

  test "counts goalie win streaks longer than ten decisions" do
    logs = ->(_id) { Array.new(12) { |i| i.even? ? {"decision" => "W"} : {} } * 2 + [{"decision" => "L"}] }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 3)

    assert_equal [{player_id: "31", streak_type: "Wins", length: 12, total_stats: 12}], analyzer.analyze(player_ids: [31], goalie_ids: [31])
  end

  test "skips goalie absences without breaking an active win streak" do
    logs = ->(_id) { [{"decision" => "W"}, {}, {"decision" => "W"}, {"decision" => "L"}, {"decision" => "W"}] }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 2)

    assert_equal [{player_id: "31", streak_type: "Wins", length: 2, total_stats: 2}], analyzer.analyze(player_ids: [31], goalie_ids: [31])
  end

  test "NHL overtime-loss decision code breaks a goalie win streak" do
    logs = ->(_id) { [{"decision" => "W"}, {"decision" => "O"}, {"decision" => "W"}] }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 1)

    wins = analyzer.analyze(player_ids: [31], goalie_ids: [31]).select { |streak| streak[:streak_type] == "Wins" }

    assert_equal [{player_id: "31", streak_type: "Wins", length: 1, total_stats: 1}], wins
  end

  test "goalie point streak counts overtime losses and stops at a regulation loss" do
    logs = ->(_id) { [{"decision" => "W"}, {}, {"decision" => "O"}, {"decision" => "W"}, {"decision" => "L"}, {"decision" => "W"}] }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 3)

    assert_equal [{player_id: "31", streak_type: "Points", length: 3, total_stats: 3, wins: 2, ot_losses: 1}],
      analyzer.analyze(player_ids: [31], goalie_ids: [31])
  end

  test "goalie point streak is omitted when it matches the win streak" do
    logs = ->(_id) { Array.new(4) { {"decision" => "W"} } + [{"decision" => "L"}, {"decision" => "O"}] }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 3)

    assert_equal ["Wins"], analyzer.analyze(player_ids: [31], goalie_ids: [31]).pluck(:streak_type)
  end

  test "quality-start streak counts starts that meet either save-percentage threshold" do
    logs = ->(_id) {
      [
        {"gamesStarted" => 1, "decision" => "L", "shotsAgainst" => 36, "goalsAgainst" => 3}, # .917
        {"gamesStarted" => 0, "shotsAgainst" => 4, "goalsAgainst" => 3},                    # relief, skipped
        {"gamesStarted" => 1, "decision" => "W", "shotsAgainst" => 20, "goalsAgainst" => 2}, # .900 on 20 shots
        {"gamesStarted" => 1, "decision" => "W", "shotsAgainst" => 30, "goalsAgainst" => 0}, # 1.000
        {"gamesStarted" => 1, "decision" => "L", "shotsAgainst" => 21, "goalsAgainst" => 2}, # .905 on 21 shots
        {"gamesStarted" => 1, "decision" => "W", "shotsAgainst" => 30, "goalsAgainst" => 0}
      ]
    }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 3)

    assert_equal [{player_id: "31", streak_type: "Quality Starts", length: 3, total_stats: 3, saves: 81, shots_against: 86}],
      analyzer.analyze(player_ids: [31], goalie_ids: [31])
  end

  test "a start without shots is not a quality start" do
    logs = ->(_id) { [{"gamesStarted" => 1, "shotsAgainst" => 0, "goalsAgainst" => 0}] + Array.new(3) { {"gamesStarted" => 1, "shotsAgainst" => 30, "goalsAgainst" => 1} } }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 1)

    assert_empty analyzer.analyze(player_ids: [31], goalie_ids: [31])
  end

  test "filters mixed season and game-type data" do
    logs = ->(_id) {
      [
        {"seasonId" => "20252026", "gameTypeId" => 2, "points" => 1},
        {"seasonId" => "20242025", "gameTypeId" => 2, "points" => 1},
        {"seasonId" => "20252026", "gameTypeId" => 3, "points" => 1}
      ]
    }
    analyzer = RodTheBot::PlayerStreaks::Analyzer.new(game_log: logs, season: "20252026", game_type: 2, minimum_length: 2)

    assert_empty analyzer.analyze(player_ids: [42])
  end
end
