module RodTheBot
  module Milestones
    # Decides whether a goal, assist, or point just moved a player past or level with
    # someone in the franchise's all-time top ten.
    class FranchiseRank
      Event = Data.define(:stat, :total, :rank, :tied, :passed, :next_up)
      Entry = Data.define(:name, :total)

      TOP = 10

      # totals: rows from Nhl::RecordsClient.franchise_skater_totals, as of before this game.
      # in_game: callable (player_id, stat) returning what the player has added in this game.
      def initialize(totals:, in_game:)
        @totals = totals
        @in_game = in_game
      end

      def event(player_id, stat)
        player_id = player_id.to_i
        current = current_totals(stat)
        total = current.delete(player_id)&.total || in_game.call(player_id, stat)
        others = current.values

        tied = others.select { |other| other.total == total }
        passed = others.select { |other| other.total == total - 1 }
        return if tied.empty? && passed.empty?

        ahead = others.select { |other| other.total > total }
        rank = ahead.size + 1
        return if rank > TOP

        Event.new(stat: stat, total: total, rank: rank, tied: tied.map(&:name), passed: passed.map(&:name), next_up: ahead.min_by(&:total))
      end

      private

      attr_reader :totals, :in_game

      def current_totals(stat)
        totals.to_h do |row|
          [row[:player_id], Entry.new(name: row[:name], total: row[stat.to_sym] + in_game.call(row[:player_id], stat))]
        end
      end
    end
  end
end
