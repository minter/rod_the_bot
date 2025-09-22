module RodTheBot
  class ScoringChangeWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter

    def perform(game_id, play_id, original_play, redis_key)
      # Use the original redis_key as the parent_key
      parent_key = redis_key

      # Create a new unique key for this scoring change post
      scoring_key = "#{redis_key}:scoring:#{Time.now.to_i}"
      @feed = NhlApi.fetch_pbp_feed(game_id)
      @play = @feed["plays"].find { |play| play["eventId"].to_s == play_id.to_s }
      home = @feed["homeTeam"]
      away = @feed["awayTeam"]

      return if @play.blank?
      return if @play["typeDescKey"] != "goal"

      # If nothing has changed on this scoring play, exit
      original_scorers = [original_play["details"]["scoringPlayerId"], original_play["details"]["assist1PlayerId"], original_play["details"]["assist2PlayerId"]]
      new_scorers = [@play["details"]["scoringPlayerId"], @play["details"]["assist1PlayerId"], @play["details"]["assist2PlayerId"]]

      return if new_scorers == original_scorers

      players = build_players(@feed)

      scoring_team_id = players[@play["details"]["scoringPlayerId"].to_s][:team_id]
      scoring_team = (home["id"] == scoring_team_id) ? home : away

      period_name = format_period_name(@play["periodDescriptor"]["number"])

      post = format_post(scoring_team, period_name, players)

      RodTheBot::Post.perform_async(post, scoring_key, parent_key, nil, goal_images(players, @play))
    end

    def build_players(feed)
      players = {}
      feed["rosterSpots"].each do |player|
        players[player["playerId"].to_s] = {
          team_id: player["teamId"],
          number: player["sweaterNumber"].to_s,
          name: "#{player["firstName"]["default"]} #{player["lastName"]["default"]}"
        }
      end
      players
    end

    def goal_images(players, play)
      images = []
      
      # Safely fetch headshot for scoring player
      if play["details"]["scoringPlayerId"].present?
        player_feed = NhlApi.fetch_player_landing_feed(play["details"]["scoringPlayerId"])
        images << player_feed&.dig("headshot")
      end
      
      # Safely fetch headshot for assist1 player
      if play["details"]["assist1PlayerId"].present?
        player_feed = NhlApi.fetch_player_landing_feed(play["details"]["assist1PlayerId"])
        images << player_feed&.dig("headshot")
      end
      
      # Safely fetch headshot for assist2 player
      if play["details"]["assist2PlayerId"].present?
        player_feed = NhlApi.fetch_player_landing_feed(play["details"]["assist2PlayerId"])
        images << player_feed&.dig("headshot")
      end
      
      images.compact # Remove any nil values
    end

    def format_post(scoring_team, period_name, players)
      post = <<~POST
        🔔 Scoring Change

        The #{scoring_team["commonName"]["default"]} goal at #{@play["timeInPeriod"]} of the #{period_name} now reads:

      POST
      post += "🚨 #{players[@play["details"]["scoringPlayerId"].to_s]&.dig(:name)} (#{@play["details"]["scoringPlayerTotal"]})\n"

      post += if @play["details"]["assist1PlayerId"].present?
        "🍎 #{players[@play["details"]["assist1PlayerId"].to_s]&.dig(:name)} (#{@play["details"]["assist1PlayerTotal"]})\n"
      else
        "🍎 Unassisted\n"
      end
      post += "🍎🍎 #{players[@play["details"]["assist2PlayerId"].to_s]&.dig(:name)} (#{@play["details"]["assist2PlayerTotal"]})\n" if @play["details"]["assist2PlayerId"].present?

      post
    end
  end
end
