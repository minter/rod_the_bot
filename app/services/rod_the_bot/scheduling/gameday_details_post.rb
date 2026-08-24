module RodTheBot
  module Scheduling
    class GamedayDetailsPost
      def build(series:, radio_url:, tickets_url:)
        lines = []
        lines.concat(series_lines(series)) if series

        links = []
        links << {"text" => "Listen live", "url" => radio_url} if radio_url.present?
        links << {"text" => "Tickets", "url" => tickets_url} if tickets_url.present?
        lines << link_line(links) if links.any?

        return if lines.empty?

        {text: lines.join("\n") + "\n", links: links}
      end

      private

      def series_lines(series)
        leader = series_leader(series)
        meeting = series[:completed_meetings] + 1
        status = if leader
          "#{leader} leads #{[series[:tracked_wins], series[:opponent_wins]].max}-#{[series[:tracked_wins], series[:opponent_wins]].min}"
        else
          "tied #{series[:tracked_wins]}-#{series[:opponent_wins]}"
        end

        [
          "Season series: #{status} (meeting #{meeting} of #{series[:total_meetings]}).",
          last_meeting_line(series[:last_meeting])
        ]
      end

      def series_leader(series)
        return series[:tracked_abbrev] if series[:tracked_wins] > series[:opponent_wins]
        series[:opponent_abbrev] if series[:opponent_wins] > series[:tracked_wins]
      end

      def last_meeting_line(game)
        date = Date.iso8601(game[:date]).strftime("%b %-d")
        suffix = outcome_suffix(game)
        "Last: #{game[:away_abbrev]} #{game[:away_score]}, #{game[:home_abbrev]} #{game[:home_score]}#{suffix} — #{date}."
      end

      def outcome_suffix(game)
        type = game[:last_period_type]
        return "" if type.blank? || type == "REG"
        return " (#{game[:overtime_periods]}OT)" if type == "OT" && game[:overtime_periods].to_i > 1

        " (#{type})"
      end

      def link_line(links)
        labels = []
        labels << "🎧 Listen live" if links.any? { |link| link["text"] == "Listen live" }
        labels << "🎟️ Tickets" if links.any? { |link| link["text"] == "Tickets" }
        labels.join(" · ")
      end
    end
  end
end
