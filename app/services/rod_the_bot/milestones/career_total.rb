module RodTheBot
  module Milestones
    class CareerTotal
      def initialize(game_id:, feed:, redis: REDIS, career_stats: Nhl::PlayerClient.method(:career_totals))
        @game_id = game_id
        @feed = feed
        @redis = redis
        @career_stats = career_stats
      end

      def for(player_id, stat)
        pregame = redis.get("pregame:#{game_id}:player:#{player_id}:#{stat}")
        return pregame.to_i + in_game(player_id, stat) if pregame

        Rails.logger.warn "No pre-game #{stat} found for player #{player_id}; using NHL career stats"
        career_stats.call(player_id).fetch(stat, 0).to_i
      end

      private

      attr_reader :game_id, :feed, :redis, :career_stats

      def in_game(player_id, stat)
        plays = feed.call&.fetch("plays", []) || []
        player_id = player_id.to_i
        goals = plays.count { |play| play["typeDescKey"] == "goal" && play.dig("details", "scoringPlayerId").to_i == player_id }
        assists = plays.count do |play|
          play["typeDescKey"] == "goal" && [play.dig("details", "assist1PlayerId"), play.dig("details", "assist2PlayerId")].compact.map(&:to_i).include?(player_id)
        end

        {"goals" => goals, "assists" => assists, "points" => goals + assists}.fetch(stat, 0)
      end
    end
  end
end
