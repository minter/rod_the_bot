module RodTheBot
  class GameStartWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = fetch_data("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      # players = build_players(@feed)
      # home_goalie = find_starting_goalie(@feed["homeTeam"], players)
      # home_goalie_record = find_goalie_record(home_goalie[:id])
      # away_goalie = find_starting_goalie(@feed["awayTeam"], players)
      # away_goalie_record = find_goalie_record(away_goalie[:id])
      officials = find_officials(game_id)
      post = format_post(@feed, officials)
      RodTheBot::Post.perform_async(post)
    end

    private

    def fetch_data(url)
      HTTParty.get(url)
    end

    def find_starting_goalie(team, players)
      team["onIce"].each do |player|
        id = player["playerId"]
        return players[id] if players.fetch(id, {})[:position] == "G"
      end
    end

    def find_goalie_record(player_id)
      player = fetch_data("https://api-web.nhle.com/v1/player/#{player_id}/landing")
      stats = player["featuredStats"]["regularSeason"]["subSeason"]
      "(#{stats["wins"]}-#{stats["losses"]}-#{stats["otLosses"]}, #{sprintf("%.2f", stats["goalsAgainstAvg"].round(2))} GAA, #{sprintf("%.3f", stats["savePctg"].round(3))} SV%)"
    end

    def find_officials(game_id)
      landing_feed = fetch_data("https://api-web.nhle.com/v1/gamecenter/#{game_id}/landing")
      officials = {}
      officials[:referees] = landing_feed["summary"]["gameInfo"]["referees"]
      officials[:lines] = landing_feed["summary"]["gameInfo"]["linesmen"]
      officials
    end

    def format_post(feed, officials)
      <<~POST
        🚦 It's puck drop at #{feed["venue"]["default"]} for #{feed["awayTeam"]["name"]["default"]} at #{feed["homeTeam"]["name"]["default"]}!
        
        Refs: #{officials[:referees].map { |r| r["default"] }.join(", ")}
        Lines: #{officials[:lines].map { |r| r["default"] }.join(", ")}
      POST
    end

    def build_players(feed)
      players = {}
      feed["rosterSpots"].each do |player|
        players[player["playerId"]] = {
          team_id: player["teamId"],
          number: player["sweaterNumber"],
          position: player["positionCode"],
          name: "#{player["firstName"]["default"]} #{player["lastName"]["default"]}",
          id: player["playerId"]
        }
      end
      players
    end
  end
end
