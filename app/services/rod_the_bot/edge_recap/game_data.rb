module RodTheBot
  module EdgeRecap
    # Picks one game's figures out of the EDGE payloads, which only expose per-game data as
    # recent-game lists and season top-10 lists.
    class GameData
      Result = Data.define(:distance, :even, :power_play, :penalty_kill, :rank, :games, :opponent_distance, :skaters, :marks)
      Skater = Data.define(:player_id, :miles, :seconds)
      Mark = Data.define(:kind, :player_id, :mph, :rank)

      def self.build(game_id:, team:, opponent:, shots:, speeds:, skaters:)
        new(game_id).build(team: team, opponent: opponent, shots: shots, speeds: speeds, skaters: skaters)
      end

      def initialize(game_id)
        @game_id = game_id.to_i
      end

      def build(team:, opponent:, shots:, speeds:, skaters:)
        recent = recent_games(team)
        entry = game_entry(team)
        distance = entry && miles(entry, "All")
        return unless distance

        Result.new(
          distance: distance,
          even: split(entry, "Even"),
          power_play: split(entry, "PP"),
          penalty_kill: split(entry, "PK"),
          rank: recent.count { |game| miles(game, "All").to_f > distance.to_f } + 1,
          games: recent.size,
          opponent_distance: game_entry(opponent)&.then { |game| miles(game, "All") },
          skaters: skater_distances(skaters),
          marks: marks(:shot, shots, "hardestShots", "shotSpeed") + marks(:speed, speeds, "topSkatingSpeeds", "skatingSpeed")
        )
      end

      private

      def recent_games(payload)
        Array(payload&.dig("skatingDistanceLast10"))
      end

      def game_entry(payload)
        recent_games(payload).find { |game| this_game?(game) }
      end

      # Matching on the game id, not the date, keeps a back-to-back against the same opponent apart.
      def this_game?(entry)
        entry["gameCenterLink"].to_s[/\d+\z/].to_i == @game_id
      end

      def miles(entry, situation)
        entry.dig("distanceSkated#{situation}", "imperial")
      end

      def split(entry, situation)
        miles(entry, situation) if entry["toi#{situation}"].to_i.positive?
      end

      def skater_distances(skaters)
        skaters.filter_map do |player_id, payload|
          entry = game_entry(payload)
          next unless entry && miles(entry, "All")

          Skater.new(player_id: player_id.to_i, miles: miles(entry, "All"), seconds: entry["toiAll"].to_i)
        end.sort_by { |skater| -skater.miles }
      end

      def marks(kind, payload, list_key, speed_key)
        Array(payload&.dig(list_key)).each_with_index.filter_map do |entry, index|
          next unless this_game?(entry)

          Mark.new(kind: kind, player_id: entry.dig("player", "id").to_i, mph: entry.dig(speed_key, "imperial"), rank: index + 1)
        end
      end
    end
  end
end
