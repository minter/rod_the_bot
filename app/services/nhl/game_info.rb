module Nhl
  class GameInfo
    class << self
      def officials(game_id)
        info = GameClient.right_rail(game_id)&.dig("gameInfo")
        return {referees: [], linesmen: []} unless info

        {
          referees: info.fetch("referees", []).pluck("default"),
          linesmen: info.fetch("linesmen", []).pluck("default")
        }
      end

      def scratches(game_id)
        boxscore = GameClient.boxscore(game_id)
        info = GameClient.right_rail(game_id)&.dig("gameInfo")
        return unless info

        away = boxscore.dig("awayTeam", "abbrev")
        home = boxscore.dig("homeTeam", "abbrev")
        return unless away && home

        scratches = %w[awayTeam homeTeam].to_h do |side|
          players = info.dig(side, "scratches") || []
          [side, players.filter_map { |player| abbreviated_name(player) }]
        end
        return if scratches.values.any? { |players| players.size > 6 }

        "#{away}: #{formatted_scratches(scratches["awayTeam"])}\n#{home}: #{formatted_scratches(scratches["homeTeam"])}"
      end

      def splits(game_id)
        GameClient.right_rail(game_id).fetch("teamGameStats", []).to_h do |split|
          category = split["category"].to_sym
          [category, {away: format_value(split["awayValue"], category), home: format_value(split["homeValue"], category)}]
        end
      end

      def roster(game_id)
        roster_from_feed(GameClient.play_by_play(game_id))
      end

      def roster_from_feed(feed)
        feed.fetch("rosterSpots", []).to_h do |player|
          [player["playerId"], {
            team_id: player["teamId"], number: player["sweaterNumber"],
            name: "#{player.dig("firstName", "default")} #{player.dig("lastName", "default")}"
          }]
        end
      end

      def opponent_team_id(game_id, team_id: ENV.fetch("NHL_TEAM_ID").to_i)
        feed = GameClient.landing(game_id)
        home_id = feed&.dig("homeTeam", "id")
        away_id = feed&.dig("awayTeam", "id")
        return unless home_id && away_id

        home_id.to_i == team_id ? away_id.to_i : home_id.to_i
      end

      private

      def abbreviated_name(player)
        first = player.dig("firstName", "default")
        last = player.dig("lastName", "default")
        "#{first[0]}. #{last}" if first.present? && last.present?
      end

      def formatted_scratches(players)
        players.present? ? players.join(", ") : "None"
      end

      def format_value(value, category)
        %i[powerPlayPctg faceoffWinningPctg].include?(category) ? "#{(value.to_f * 100).round(1)}%" : value
      end
    end
  end
end
