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
        games = game_log.call(player_id)
        return games unless games.first&.key?("seasonId") || games.first&.key?("gameTypeId")

        games.select { |game| game["seasonId"].to_s == season && game["gameTypeId"].to_i == game_type }
      end

      def skater_streaks(player_id, games)
        STAT_TYPES.filter_map do |label, stat|
          result = active_streak(games) { |game| game[stat].to_i }
          streak(player_id, label, result) if result[:length] >= minimum_length
        end
      end

      def goalie_streaks(player_id, games)
        wins = goalie_win_streak(games)
        points = goalie_point_streak(games)
        quality_starts = quality_start_streak(games)

        streaks = []
        streaks << streak(player_id, "Wins", wins) if wins[:length] >= minimum_length
        streaks << streak(player_id, "Points", points) if points[:length] >= minimum_length && points[:length] > wins[:length]
        streaks << streak(player_id, "Quality Starts", quality_starts) if quality_starts[:length] >= minimum_length
        streaks
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

      # Games without a decision (relief appearances, pulled starters) neither extend nor break the streak.
      def goalie_decisions(games)
        games.filter_map do |game|
          decision = game["decision"].to_s.upcase
          if decision == "W" || game["wins"].to_i.positive?
            :win
          elsif %w[O OTL].include?(decision) || game["otLosses"].to_i.positive? || game["otl"].to_i.positive?
            :ot_loss
          elsif decision == "L" || game["losses"].to_i.positive?
            :loss
          end
        end
      end

      def goalie_win_streak(games)
        length = goalie_decisions(games).take_while { |decision| decision == :win }.length
        {length: length, total_stats: length}
      end

      def goalie_point_streak(games)
        decisions = goalie_decisions(games).take_while { |decision| decision != :loss }
        wins = decisions.count(:win)
        {length: decisions.length, total_stats: decisions.length, wins: wins, ot_losses: decisions.length - wins}
      end

      # Quality start: .917 save percentage, or .885 on 20 shots or fewer, compared at the
      # three decimals save percentage is published with. Only starts count.
      def quality_start_streak(games)
        starts = games.select { |game| game["gamesStarted"].to_i.positive? }
        streak_games = starts.take_while { |game| quality_start?(game) }
        shots = streak_games.sum { |game| game["shotsAgainst"].to_i }
        saves = shots - streak_games.sum { |game| game["goalsAgainst"].to_i }
        {length: streak_games.length, total_stats: streak_games.length, saves: saves, shots_against: shots}
      end

      def quality_start?(game)
        shots = game["shotsAgainst"].to_i
        return false unless shots.positive?

        save_pct = Rational((shots - game["goalsAgainst"].to_i) * 1000, shots).round
        save_pct >= 917 || (shots <= 20 && save_pct >= 885)
      end

      def streak(player_id, type, result)
        {player_id: player_id.to_s, streak_type: type, **result}
      end
    end
  end
end
