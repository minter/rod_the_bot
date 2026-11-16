module RodTheBot
  module EdgeRecap
    class Formatter
      SKATER_COUNT = 3
      # A rank among fewer games than this says nothing worth posting.
      MINIMUM_RANKED_GAMES = 3

      def initialize(result:, names:, team_name:, opponent_name:, home:, limit: PostThread.content_limit)
        @result = result
        @names = names
        @team_name = team_name
        @opponent_name = opponent_name
        @home = home
        @limit = limit
      end

      def posts
        [team_post, skater_post, marks_post].compact
      end

      private

      def team_post
        lines = ["#{@team_name} skated #{miles(@result.distance)} mi#{rank_phrase}"]
        lines << "#{@opponent_name}: #{miles(@result.opponent_distance)} mi" if @result.opponent_distance
        splits = {"Even strength" => @result.even, "Power play" => @result.power_play, "Penalty kill" => @result.penalty_kill}
          .compact.map { |label, distance| "#{label} #{miles(distance)}" }

        ["⛸️ EDGE recap: #{@team_name} #{@home ? "vs." : "at"} #{@opponent_name}", lines.join("\n"), splits.join(" · ").presence]
          .compact.join("\n\n")
      end

      def rank_phrase
        games = @result.games
        return "" if games < MINIMUM_RANKED_GAMES

        position = case @result.rank
        when 1 then "most"
        when games then "fewest"
        else "#{@result.rank.ordinalize} most"
        end
        " (#{position} in their last #{games} games)"
      end

      def skater_post
        lines = @result.skaters.filter_map do |skater|
          name = @names.call(skater.player_id)
          "#{name}: #{miles(skater.miles)} mi in #{clock(skater.seconds)}" if name
        end.first(SKATER_COUNT)
        return if lines.empty?

        "⛸️ Most ice covered:\n\n#{lines.join("\n")}"
      end

      def marks_post
        header = "📈 New on the #{possessive(@team_name)} season top 10:\n\n"
        lines = @result.marks.filter_map { |mark| mark_line(mark) }
        lines.pop while lines.any? && (header + lines.join("\n")).length > @limit
        return if lines.empty?

        header + lines.join("\n")
      end

      def mark_line(mark)
        name = @names.call(mark.player_id)
        return unless name

        superlative = (mark.kind == :shot) ? "hardest" : "fastest"
        standing = (mark.rank == 1) ? superlative : "#{mark.rank.ordinalize} #{superlative}"
        if mark.kind == :shot
          "💥 #{name}: #{speed(mark.mph)} mph shot (#{standing})"
        else
          "⚡ #{name}: #{speed(mark.mph)} mph (#{standing})"
        end
      end

      def possessive(name)
        name.end_with?("s") ? "#{name}'" : "#{name}'s"
      end

      def miles(value)
        format("%.2f", value)
      end
      alias_method :speed, :miles

      def clock(seconds)
        format("%d:%02d", seconds / 60, seconds % 60)
      end
    end
  end
end
