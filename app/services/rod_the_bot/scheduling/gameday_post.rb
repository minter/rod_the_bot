module RodTheBot
  module Scheduling
    class GamedayPost
      include ActionView::Helpers::TextHelper
      include ActiveSupport::Inflector

      def build(game:, away:, home:, tracked:, time:, television:, preseason:, postseason:, seed_labels: {}, series_status: nil)
        title = preseason ? "Preseason Gameday" : (postseason ? "Playoff Gameday" : "Gameday")
        lines = ["🗣️ It's a #{tracked[:team_name]} #{title}!", ""]
        lines += [playoff_status_line(series_status), ""] if postseason && series_status
        lines += team_lines(away, seed_labels, show_record: !preseason && !postseason)
        lines += ["", "at", ""]
        lines += team_lines(home, seed_labels, show_record: !preseason && !postseason)
        lines += ["", "⏰ #{time}", "📍 #{game.dig("venue", "default")}", "📺 #{television}"]
        lines.join("\n") + "\n"
      end

      private

      def team_lines(team, seeds, show_record:)
        seed = seeds[team[:abbrev]] ? "(#{seeds[team[:abbrev]]}) " : ""
        ["#{seed}#{team[:team_name]}", (record(team) if show_record)].compact
      end

      def playoff_status_line(status)
        "Round #{status["round"]}, Game #{status["gameNumberOfSeries"]} — #{series_state(status)}"
      end

      def series_state(status)
        top = status["topSeedWins"]
        bottom = status["bottomSeedWins"]
        return "Series tied #{top}-#{bottom}" if top == bottom
        top > bottom ? "#{status["topSeedTeamAbbrev"]} leads #{top}-#{bottom}" : "#{status["bottomSeedTeamAbbrev"]} leads #{bottom}-#{top}"
      end

      def record(team)
        line = "(#{team[:wins]}-#{team[:losses]}-#{team[:ot]}, #{team[:points]} #{"point".pluralize(team[:points])})"
        line += "\n#{ordinalize team[:division_rank]} in the #{team[:division_name]}" unless team[:division_name] == "Unknown"
        line
      end
    end
  end
end
