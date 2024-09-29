module RodTheBot
  class GameStartWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = fetch_data("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      home_goalie = find_starting_goalie("homeTeam")
      home_goalie_record = find_goalie_record(home_goalie["playerId"])
      away_goalie = find_starting_goalie("awayTeam")
      away_goalie_record = find_goalie_record(away_goalie["playerId"])
      officials = NhlApi.officials(game_id)
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

    def format_post(feed, officials, home_goalie, home_goalie_record, away_goalie, away_goalie_record)
      <<~POST
        🚦 It's puck drop at #{feed["venue"]["default"]} for #{feed["awayTeam"]["name"]["default"]} at #{feed["homeTeam"]["name"]["default"]}!
        
        Starting Goalies:
        #{feed["homeTeam"]["abbrev"]}: ##{home_goalie["sweaterNumber"]} #{home_goalie["name"]["default"]} #{home_goalie_record}
        #{feed["awayTeam"]["abbrev"]}: ##{away_goalie["sweaterNumber"]} #{away_goalie["name"]["default"]} #{away_goalie_record}

        Referees: #{officials[:referees].join(", ")}
        Lines: #{officials[:linesmen].join(", ")}
      POST
    end
  end
end
