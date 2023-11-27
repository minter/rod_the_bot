module RodTheBot
  class GameStartWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = fetch_game_data(game_id)
      players = build_players(@feed)
      home_goalie = find_starting_goalie(@feed["homeTeam"], players)
      home_goalie_record = find_goalie_record(home_goalie[:id])
      away_goalie = find_starting_goalie(@feed["awayTeam"], players)
      away_goalie_record = find_goalie_record(away_goalie[:id])
      officials = find_officials(game_id)
      post = format_post(@feed, home_goalie, away_goalie, officials, home_goalie_record, away_goalie_record)
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

    def find_goalie_record(player_id)
      player = HTTParty.get("https://api-web.nhle.com/v1/player/#{player_id}/landing")
      stats = player["featuredStats"]["regularSeason"]["subSeason"]
      "(#{stats["wins"]}-#{stats["losses"]}-#{stats["otLosses"]}, #{stats["goalsAgainstAvg"].round(2)} GAA, #{stats["savePctg"].round(3)} SV%)"
    end

    def find_officials(game_id)
      landing_feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/landing")
      officials = {}
      officials[:referees] = landing_feed["summary"]["gameInfo"]["referees"]
      officials[:lines] = landing_feed["summary"]["gameInfo"]["linesmen"]
      officials
    end

    def format_post(feed, home_goalie, away_goalie, officials, home_goalie_record, away_goalie_record)
      <<~POST
        🚦 It's puck drop at #{feed["venue"]["default"]} for #{feed["awayTeam"]["name"]["default"]} at #{feed["homeTeam"]["name"]["default"]}!
        
        Starting Goalies:
        #{feed["homeTeam"]["abbrev"]}: #{home_goalie[:name]} #{home_goalie_record}
        #{feed["awayTeam"]["abbrev"]}: #{away_goalie[:name]} #{away_goalie_record}

        Refs: #{officials[:referees].collect { |r| r["default"] }.join(", ")}
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
          name: player["firstName"]["default"] + " " + player["lastName"]["default"],
          id: player["playerId"]
        }
      end
      players
    end
  end
end
