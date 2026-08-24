module RodTheBot
  module Scheduling
    class GamedayPost
      include ActionView::Helpers::TextHelper
      include ActiveSupport::Inflector

      def build(game:, away:, home:, tracked:, starts_at:, time_zone:, television:, preseason:, postseason:, seed_labels: {}, series_status: nil)
        title = if preseason
          "Preseason Gameday"
        else
          (postseason ? "Playoff Gameday" : "Gameday")
        end
        lines = ["🗣️ It's a #{tracked[:team_name]} #{title}!", ""]
        lines += ["🌍 #{special_event_name(game)}", ""] if special_event_name(game)
        lines += [playoff_status_line(series_status), ""] if postseason && series_status
        lines += team_lines(away, seed_labels, show_record: !preseason && !postseason)
        lines += ["", "at", ""]
        lines += team_lines(home, seed_labels, show_record: !preseason && !postseason)
        lines += [""] + time_lines(game, starts_at, time_zone)
        lines += ["📍 #{game.dig("venue", "default")}", "📺 #{television}"]
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
        (top > bottom) ? "#{status["topSeedTeamAbbrev"]} leads #{top}-#{bottom}" : "#{status["bottomSeedTeamAbbrev"]} leads #{bottom}-#{top}"
      end

      def record(team)
        return unless %i[wins losses ot points].all? { |key| team[key].present? }

        line = "(#{team[:wins]}-#{team[:losses]}-#{team[:ot]}, #{team[:points]} #{"point".pluralize(team[:points])})"
        line += "\n#{ordinalize team[:division_rank]} in the #{team[:division_name]}" unless team[:division_name] == "Unknown"
        line
      end

      def special_event_name(game)
        game.dig("specialEvent", "name", "default").presence
      end

      def time_lines(game, starts_at, time_zone)
        lines = ["⏰ #{format_time(starts_at, time_zone)}"]
        venue_time_zone = game["venueTimezone"].presence

        if special_event_name(game) && venue_time_zone && venue_time_zone != time_zone
          lines << "🌐 #{format_time(starts_at, venue_time_zone)} local time"
        end

        lines
      end

      def format_time(starts_at, time_zone)
        starts_at.in_time_zone(time_zone).strftime("%l:%M %p %Z").strip
      end
    end
  end
end
