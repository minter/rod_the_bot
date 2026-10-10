module RodTheBot
  module Milestones
    class UpcomingFormatter
      def header(playoffs:)
        playoffs ? "🎯 Upcoming Milestones (Playoffs):\n\n" : "🎯 Upcoming Milestones:\n\n"
      end

      def line(player_name, entry)
        "#{urgency(entry.remaining)} #{player_name}: #{entry.remaining} #{entry.type.pluralize(entry.remaining)} away from #{entry.target}\n"
      end

      private

      def urgency(remaining)
        case remaining
        when 1 then "🔥"
        when 2..3 then "⚡"
        else "📈"
        end
      end
    end
  end
end
