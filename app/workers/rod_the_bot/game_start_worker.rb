module RodTheBot
  class GameStartWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = fetch_data("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      home_goalie = find_starting_goalie("homeTeam")
      home_goalie_record = find_goalie_record(home_goalie["playerId"])
      away_goalie = find_starting_goalie("awayTeam")
      away_goalie_record = find_goalie_record(away_goalie["playerId"])
      officials = find_officials(game_id)
      post = format_post(@feed, officials, home_goalie, home_goalie_record, away_goalie, away_goalie_record)
      RodTheBot::Post.perform_async(post)
    end

    private

    def fetch_data(url)
      HTTParty.get(url)
    end

    def find_starting_goalie(team)
      @feed["summary"]["iceSurface"][team]["goalies"].first
    end

    def find_goalie_record(player_id)
      season = (@feed["gameType"] == 3) ? "playoffs" : "regularSeason"
      player = fetch_data("https://api-web.nhle.com/v1/player/#{player_id}/landing")
      stats = player["featuredStats"][season]["subSeason"]
      "(#{stats["wins"]}-#{stats["losses"]}-#{stats["otLosses"]}, #{sprintf("%.2f", stats["goalsAgainstAvg"].round(2))} GAA, #{sprintf("%.3f", stats["savePctg"].round(3))} SV%)"
    end

    def find_officials(game_id)
      landing_feed = fetch_data("https://api-web.nhle.com/v1/gamecenter/#{game_id}/landing")
      officials = {}
      officials[:referees] = landing_feed["summary"]["gameInfo"]["referees"]
      officials[:lines] = landing_feed["summary"]["gameInfo"]["linesmen"]
      officials
    end

    def format_post(feed, officials, home_goalie, home_goalie_record, away_goalie, away_goalie_record)
      <<~POST
        🚦 It's puck drop at #{feed["venue"]["default"]} for #{feed["awayTeam"]["name"]["default"]} at #{feed["homeTeam"]["name"]["default"]}!
        
        Starting Goalies:
        #{feed["homeTeam"]["abbrev"]}: ##{home_goalie["sweaterNumber"]} #{home_goalie["name"]["default"]} #{home_goalie_record}
        #{feed["awayTeam"]["abbrev"]}: ##{away_goalie["sweaterNumber"]} #{away_goalie["name"]["default"]} #{away_goalie_record}

        Refs: #{officials[:referees].map { |r| r["default"] }.join(", ")}
        Lines: #{officials[:lines].map { |r| r["default"] }.join(", ")}
      POST
    end
  end
end
