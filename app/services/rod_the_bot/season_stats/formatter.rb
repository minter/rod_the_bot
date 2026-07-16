module RodTheBot
  module SeasonStats
    class Formatter
      include ActionView::Helpers::TextHelper

      def initialize(season_type:, team_name:)
        @season_type, @team_name = season_type, team_name
      end

      def goalie(players)
        body = players.sort_by { |_, value| value[:wins] }.reverse.map { |_, p| "#{p[:name]}: #{p[:wins]}-#{p[:losses]}-#{p[:overtime_losses]}, #{p[:save_percentage]} SV%, #{p[:goals_against_average]} GAA" }.join("\n")
        "🥅 #{@season_type} goaltending stats for the #{@team_name}\n\n#{body}\n"
      end

      def skaters(players, stat, icon:, title:)
        body = players.map { |_, p| yield(p) }.join("\n")
        "#{icon} #{@season_type} #{title} for the #{@team_name}\n\n#{body}\n"
      end

      def team_rankings(rankings, part:)
        keys = (part == 1) ? [[:average_goals_scored, "Average Goals Scored"], [:average_goals_allowed, "Average Goals Allowed"], [:power_play_percentage, "Power Play Percentage"], [:penalty_kill_percentage, "Penalty Kill Percentage"]] : [[:shots_per_game, "Shots Per Game"], [:shots_allowed_per_game, "Shots Allowed Per Game"], [:faceoff_percentage, "Faceoff Percentage"], [:points_percentage, "Points Percentage"]]
        body = keys.map { |key, label| "#{label}: #{rankings[key][:value]} (Rank: #{rankings[key][:rank]})" }.join("\n")
        "📊 #{@season_type} stats and NHL ranks for the #{@team_name} (#{part}/2)\n\n#{body}\n"
      end
    end
  end
end
