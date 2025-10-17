module RodTheBot
  class PregameStatsWorker
    include Sidekiq::Worker

    def perform(game_id)
      @game_id = game_id
      
      # Get the roster for this game
      roster = NhlApi.game_rosters(game_id)
      
      # Store pre-game career stats for all players in the game
      roster.each do |player_id, player_data|
        store_pregame_stats(player_id)
      end
    end

    private

    def store_pregame_stats(player_id)
      # Fetch current career stats from the landing page API (more reliable than stats API)
      response = HTTParty.get("https://api-web.nhle.com/v1/player/#{player_id}/landing")
      return unless response.success?

      player_data = response.parsed_response
      career_stats = player_data.dig("careerTotals", "regularSeason")
      return unless career_stats

      # Store in Redis with expiration (keep for 7 days)
      redis_key_prefix = "pregame:#{@game_id}:player:#{player_id}"
      
      REDIS.setex("#{redis_key_prefix}:goals", 604800, career_stats["goals"] || 0)
      REDIS.setex("#{redis_key_prefix}:assists", 604800, career_stats["assists"] || 0)
      REDIS.setex("#{redis_key_prefix}:points", 604800, career_stats["points"] || 0)
      
      # For goalies, also store wins and shutouts
      if player_data["position"] == "G"
        REDIS.setex("#{redis_key_prefix}:wins", 604800, career_stats["wins"] || 0)
        REDIS.setex("#{redis_key_prefix}:shutouts", 604800, career_stats["shutouts"] || 0)
      end
    end
  end
end

