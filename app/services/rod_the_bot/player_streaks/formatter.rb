module RodTheBot
  module PlayerStreaks
    class Formatter
      def chunks(streaks, season_type:)
        header = (season_type == "Playoffs") ? "🔥 Active Streaks (Playoffs):\n\n" : "🔥 Active Streaks:\n\n"
        PostThread.split_lines(streaks.map { |streak| line(streak) }, header: header)
      end

      def line(streak)
        "#{streak[:player_name]}: #{description(streak)}\n"
      end

      private

      def description(streak)
        if streak[:streak_type] == "Quality Starts"
          "#{streak[:length]} straight quality starts (#{save_percentage(streak[:saves], streak[:shots_against])} SV%)"
        elsif streak.key?(:ot_losses)
          "#{streak[:length]}-game point streak (#{streak[:wins]}-0-#{streak[:ot_losses]})"
        else
          "#{streak[:length]}-game #{streak[:streak_type].downcase.singularize} streak (#{streak[:total_stats]} total)"
        end
      end

      def save_percentage(saves, shots)
        thousandths = Rational(saves * 1000, shots).round
        (thousandths >= 1000) ? "1.000" : format(".%03d", thousandths)
      end
    end
  end
end
