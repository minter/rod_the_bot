module RodTheBot
  module PlayerStreaks
    class Formatter
      def chunks(streaks, season_type:)
        header = season_type == "Playoffs" ? "🔥 Active Streaks (Playoffs):\n\n" : "🔥 Active Streaks:\n\n"
        PostThread.split_lines(streaks.map { |streak| line(streak) }, header: header)
      end

      def line(streak)
        "#{streak[:player_name]}: #{streak[:length]}-game #{streak[:streak_type].downcase} streak (#{streak[:total_stats]} total)\n"
      end
    end
  end
end
