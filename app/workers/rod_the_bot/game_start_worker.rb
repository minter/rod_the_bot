module RodTheBot
  class GameStartWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = NhlApi.fetch_pbp_feed(game_id)
      home_goalie = find_starting_goalie("homeTeam")
      home_goalie_record = find_goalie_record(home_goalie["playerId"])
      away_goalie = find_starting_goalie("awayTeam")
      away_goalie_record = find_goalie_record(away_goalie["playerId"])
      officials = NhlApi.officials(game_id)
      scratches = NhlApi.scratches(game_id)
      post = format_post(@feed, officials, home_goalie, home_goalie_record, away_goalie, away_goalie_record, scratches)
      RodTheBot::Post.perform_async(post)
    end

    private

    def find_starting_goalie(team)
      @feed["summary"]["iceSurface"][team]["goalies"].first
    end

    def find_goalie_record(player_id)
      season = (@feed["gameType"] == 3) ? "playoffs" : "regularSeason"
      player = NhlApi.fetch_player_landing_feed(player_id)
      stats = player["featuredStats"][season]["subSeason"]
      "(#{stats["wins"]}-#{stats["losses"]}-#{stats["otLosses"]}, #{sprintf("%.2f", stats["goalsAgainstAvg"].round(2))} GAA, #{sprintf("%.3f", stats["savePctg"].round(3))} SV%)"
    end

    def format_post(feed, officials, home_goalie, home_goalie_record, away_goalie, away_goalie_record, scratches)
      post = <<~POST
        🚦 It's puck drop at #{feed["venue"]["default"]} for #{feed["awayTeam"]["name"]["default"]} at #{feed["homeTeam"]["name"]["default"]}!
        
        Starting Goalies:
        #{feed["homeTeam"]["abbrev"]}: ##{home_goalie["sweaterNumber"]} #{home_goalie["name"]["default"]} #{home_goalie_record}
        #{feed["awayTeam"]["abbrev"]}: ##{away_goalie["sweaterNumber"]} #{away_goalie["name"]["default"]} #{away_goalie_record}

        Referees: #{officials[:referees].join(", ")}
        Lines: #{officials[:linesmen].join(", ")}
      POST
      post += "\n\nScratches:\n#{scratches}" if scratches
      post
    end
  end
end
