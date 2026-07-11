require "set"

module RodTheBot
  module PlayerStreaks
    class Analyzer
      STAT_TYPES = {"Points" => "points", "Goals" => "goals", "Assists" => "assists"}.freeze

      def initialize(game_log:, season:, game_type:, minimum_length: 3)
        @game_log = game_log
        @season = season.to_s
        @game_type = game_type.to_i
        @minimum_length = minimum_length.to_i
      end

      def analyze(player_ids:, goalie_ids: [])
        goalie_ids = goalie_ids.map(&:to_s).to_set
        player_ids.flat_map do |player_id|
          games = recent_games(player_id)
          next [] if games.empty?

          goalie_ids.include?(player_id.to_s) ? goalie_streaks(player_id, games) : skater_streaks(player_id, games)
        end
      end

      private

      attr_reader :game_log, :season, :game_type, :minimum_length

      def recent_games(player_id)
        games = game_log.call(player_id, 20)
        if games.first&.key?("seasonId") || games.first&.key?("gameTypeId")
          games = games.select { |game| game["seasonId"].to_s == season && game["gameTypeId"].to_i == game_type }
        end
        games.first(10)
      end

      def skater_streaks(player_id, games)
        STAT_TYPES.filter_map do |label, stat|
          result = active_streak(games) { |game| game[stat].to_i }
          streak(player_id, label, result) if result[:length] >= minimum_length
        end
      end

      def goalie_streaks(player_id, games)
        result = goalie_win_streak(games)
        result[:length] >= minimum_length ? [streak(player_id, "Wins", result)] : []
      end

      def active_streak(games)
        values = []
        games.each do |game|
          value = yield(game)
          break unless value.positive?
          values << value
        end
        {length: values.length, total_stats: values.sum}
      end

      def goalie_win_streak(games)
        wins = []
        games.each do |game|
          decision = game["decision"].to_s.upcase
          played = %w[W L O OTL].include?(decision) || %w[wins losses otLosses otl].any? { |key| game[key].to_i.positive? }
          next unless played
          break unless decision == "W" || game["wins"].to_i.positive?
          wins << 1
        end
        {length: wins.length, total_stats: wins.sum}
      end

      def streak(player_id, type, result)
        {player_id: player_id.to_s, streak_type: type, **result}
      end
    end
  end
end
