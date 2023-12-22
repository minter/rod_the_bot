module RodTheBot
  class GoalWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    def perform(game_id, play)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      @play_id = play["eventId"]
      @play = @feed["plays"].find { |play| play["eventId"] == @play_id }

      return if @play.blank?

      # Skip goals in the shootout
      return if @play["periodDescriptor"]["periodType"] == "SO"

      home = @feed["homeTeam"]
      away = @feed["awayTeam"]
      if home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        @your_team = home
        @their_team = away
      else
        @your_team = away
        @their_team = home
      end

      players = build_players(@feed)

      original_play = @play.deep_dup

      if @play["details"]["scoringPlayerId"].blank?
        RodTheBot::GoalWorker.perform_in(60, game_id, @play)
        return
      end

      post = if players[@play["details"]["scoringPlayerId"]][:team_id] == ENV["NHL_TEAM_ID"].to_i
        "🎉 #{@your_team["name"]["default"]} GOOOOOOOAL!\n\n"
      else
        "👎 #{@their_team["name"]["default"]} Goal\n\n"
      end

      post += "🚨 #{players[@play["details"]["scoringPlayerId"]][:name]} (#{@play["details"]["scoringPlayerTotal"]})\n"

      post += if @play["details"]["assist1PlayerId"].present?
        "🍎 #{players[@play["details"]["assist1PlayerId"]][:name]} (#{@play["details"]["assist1PlayerTotal"]})\n"
      else
        "🍎 Unassisted\n"
      end
      post += "🍎🍎 #{players[@play["details"]["assist2PlayerId"]][:name]} (#{@play["details"]["assist2PlayerTotal"]})\n" if @play["details"]["assist2PlayerId"].present?

      post += "⏱️  #{@play["timeInPeriod"]} #{ordinalize(@play["period"])} Period\n\n"
      post += "#{away["abbrev"]} #{@play["details"]["awayScore"]} - #{home["abbrev"]} #{@play["details"]["homeScore"]}\n"
      RodTheBot::Post.perform_async(post)
      RodTheBot::ScoringChangeWorker.perform_in(600, game_id, play["eventId"], original_play)
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
