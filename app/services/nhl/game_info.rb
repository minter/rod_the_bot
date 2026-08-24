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

      def opponent_team_id(game_id, team_id: ENV.fetch("NHL_TEAM_ID").to_i)
        feed = GameClient.landing(game_id)
        home_id = feed&.dig("homeTeam", "id")
        away_id = feed&.dig("awayTeam", "id")
        return unless home_id && away_id

        (home_id.to_i == team_id) ? away_id.to_i : home_id.to_i
      end

      def season_series(game_id, team_id: ENV.fetch("NHL_TEAM_ID").to_i)
        games = Array(GameClient.right_rail(game_id)["seasonSeries"])
        completed = games.select { |game| completed_series_game?(game) }
        return if completed.empty?

        tracked_abbrev = games.filter_map { |game| team_for(game, team_id)&.dig("abbrev") }.first
        opponent_abbrev = games.filter_map { |game| opponent_for(game, team_id)&.dig("abbrev") }.first
        return unless tracked_abbrev && opponent_abbrev

        wins = completed.each_with_object({tracked: 0, opponent: 0}) do |game, totals|
          tracked_score = team_for(game, team_id).to_h["score"].to_i
          opponent_score = opponent_for(game, team_id).to_h["score"].to_i
          totals[:tracked] += 1 if tracked_score > opponent_score
          totals[:opponent] += 1 if opponent_score > tracked_score
        end

        {
          tracked_abbrev: tracked_abbrev,
          opponent_abbrev: opponent_abbrev,
          tracked_wins: wins[:tracked],
          opponent_wins: wins[:opponent],
          completed_meetings: completed.size,
          total_meetings: games.size,
          last_meeting: normalize_series_game(completed.max_by { |game| game["gameDate"].to_s })
        }
      end

      private

      def completed_series_game?(game)
        game.dig("awayTeam", "score").present? && game.dig("homeTeam", "score").present?
      end

      def team_for(game, team_id)
        %w[awayTeam homeTeam].filter_map { |side| game[side] }.find do |team|
          team["id"].to_i == team_id.to_i
        end
      end

      def opponent_for(game, team_id)
        %w[awayTeam homeTeam].filter_map { |side| game[side] }.find do |team|
          team["id"].to_i != team_id.to_i
        end
      end

      def normalize_series_game(game)
        {
          date: game["gameDate"],
          away_abbrev: game.dig("awayTeam", "abbrev"),
          away_score: game.dig("awayTeam", "score"),
          home_abbrev: game.dig("homeTeam", "abbrev"),
          home_score: game.dig("homeTeam", "score"),
          last_period_type: game.dig("gameOutcome", "lastPeriodType"),
          overtime_periods: game.dig("gameOutcome", "otPeriods")
        }
      end

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
