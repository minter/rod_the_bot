module RodTheBot
  class ScoringChangeWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    def perform(game_id, play_id, original_play)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      @play = @feed["plays"].find { |play| play["eventId"].to_i == play_id.to_i }
      home = @feed["homeTeam"]
      away = @feed["awayTeam"]

      return if @play.blank?
      return if @play["typeDescKey"] != "goal"

      # If nothing has changed on this scoring play, exit
      original_scorers = [original_play["details"]["scoringPlayerId"], original_play["details"]["assist1PlayerId"], original_play["details"]["assist2PlayerId"]]
      new_scorers = [@play["details"]["scoringPlayerId"], @play["details"]["assist1PlayerId"], @play["details"]["assist2PlayerId"]]
      return if new_scorers == original_scorers

      players = build_players(@feed)

      scoring_team_id = players[@play["details"]["scoringPlayerId"]][:team_id]
      scoring_team = (home["id"] == scoring_team_id) ? home : away

      post = <<~POST
        🔔 Scoring Change

        The #{scoring_team["name"]["default"]} goal at #{@play["timeInPeriod"]} of the #{ordinalize(@play["period"])} period now reads:

      POST
      post += "🚨 #{players[@play["details"]["scoringPlayerId"]][:name]} (#{@play["details"]["scoringPlayerTotal"]})\n"

      post += if @play["details"]["assist1PlayerId"].present?
        "🍎 #{players[@play["details"]["assist1PlayerId"]][:name]} (#{@play["details"]["assist1PlayerTotal"]})\n"
      else
        "🍎 Unassisted\n"
      end
      post += "🍎🍎 #{players[@play["details"]["assist2PlayerId"]][:name]} (#{@play["details"]["assist2PlayerTotal"]})\n" if @play["details"]["assist2PlayerId"].present?

      RodTheBot::Post.perform_async(post)
    end

    def build_players(feed)
      players = {}
      feed["rosterSpots"].each do |player|
        players[player["playerId"]] = {
          team_id: player["teamId"],
          number: player["sweaterNumber"],
          name: player["firstName"]["default"] + " " + player["lastName"]["default"]
        }
      end
      players
    end
  end
end
