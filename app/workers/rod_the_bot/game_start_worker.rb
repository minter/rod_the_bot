module RodTheBot
  class GameStartWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      home = @feed["homeTeam"]
      away = @feed["awayTeam"]

      players = build_players(@feed)
      home_goalie = nil
      away_goalie = nil

      home["onIce"].each do |player|
        id = player["playerId"]
        if players[id][:position] == "G"
          home_goalie = players[id]
        end
      end

      away["onIce"].each do |player|
        id = player["playerId"]
        if players[id][:position] == "G"
          away_goalie = players[id]
        end
      end

      post = <<~POST
        🚦 We're ready for puck drop at #{@feed["venue"]["default"]}!
        
        #{away["name"]["default"]} at #{home["name"]["default"]} is about to begin!

        Starting Goaltenders:

        #{home["abbrev"]}: #{home_goalie[:name]}
        #{away["abbrev"]}: #{away_goalie[:name]}
      POST
      RodTheBot::Post.perform_async(post)
    end

    def build_players(feed)
      players = {}
      feed["rosterSpots"].each do |player|
        players[player["playerId"]] = {
          team_id: player["teamId"],
          number: player["sweaterNumber"],
          position: player["positionCode"],
          name: player["firstName"]["default"] + " " + player["lastName"]["default"]
        }
      end
      players
    end
  end
end
