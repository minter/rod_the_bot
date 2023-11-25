module RodTheBot
  class GameStartWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = fetch_game_data(game_id)
      players = build_players(@feed)
      home_goalie = find_starting_goalie(@feed["homeTeam"], players)
      away_goalie = find_starting_goalie(@feed["awayTeam"], players)
      officials = find_officials(game_id)
      post = format_post(@feed, home_goalie, away_goalie, officials)
      RodTheBot::Post.perform_async(post)
    end

    private

    def fetch_game_data(game_id)
      HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
    end

    def find_starting_goalie(team, players)
      team["onIce"].each do |player|
        id = player["playerId"]
        return players[id] if players[id][:position] == "G"
      end
    end

    def find_officials(game_id)
      landing_feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/landing")
      officials = {}
      officials[:referees] = landing_feed["summary"]["gameInfo"]["referees"]
      officials[:lines] = landing_feed["summary"]["gameInfo"]["linesmen"]
      officials
    end

    def format_post(feed, home_goalie, away_goalie, officials)
      <<~POST
        🚦 We're ready for puck drop at #{feed["venue"]["default"]}!
        
        #{feed["awayTeam"]["name"]["default"]} at #{feed["homeTeam"]["name"]["default"]} is about to begin!

        Starting Goalies:
        #{feed["homeTeam"]["abbrev"]}: #{home_goalie[:name]}
        #{feed["awayTeam"]["abbrev"]}: #{away_goalie[:name]}

        Referees: #{officials[:referees].collect { |r| r["default"] }.join(", ")}
        Lines: #{officials[:lines].collect { |r| r["default"] }.join(", ")}
      POST
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
