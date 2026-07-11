require "test_helper"

class RodTheBot::SeasonStats::FormatterTest < ActiveSupport::TestCase
  setup { @formatter = RodTheBot::SeasonStats::Formatter.new(season_type: "2025-2026 Season", team_name: "Hurricanes") }

  test "orders goalies by wins" do
    post = @formatter.goalie({1 => goalie("#31 Frederik Andersen", 10), 2 => goalie("#52 Pyotr Kochetkov", 15)})

    assert_operator post.index("Kochetkov"), :<, post.index("Andersen")
    assert_includes post, "15-3-1, 0.920 SV%, 2.10 GAA"
  end

  test "formats a selected skater leaderboard" do
    post = @formatter.skaters([[1, {name: "#20 Sebastian Aho", goals: 30}]], :goals, icon: "🚨", title: "goal scoring leaders") { |player| "#{player[:name]}: #{player[:goals]} goals" }

    assert_includes post, "🚨 2025-2026 Season goal scoring leaders for the Hurricanes"
    assert_includes post, "#20 Sebastian Aho: 30 goals"
  end

  test "formats the first team ranking page" do
    rankings = %i[average_goals_scored average_goals_allowed power_play_percentage penalty_kill_percentage].to_h { |key| [key, {value: "3.2", rank: "5th"}] }

    post = @formatter.team_rankings(rankings, part: 1)

    assert_includes post, "Average Goals Scored: 3.2 (Rank: 5th)"
    assert_includes post, "Penalty Kill Percentage: 3.2 (Rank: 5th)"
  end

  private

  def goalie(name, wins)
    {name: name, wins: wins, losses: 3, overtime_losses: 1, save_percentage: "0.920", goals_against_average: "2.10"}
  end
end
