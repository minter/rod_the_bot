module RodTheBot
  class GameStartWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = NhlApi.fetch_pbp_feed(game_id)
      home_goalie = find_starting_goalie("homeTeam")
      home_goalie_record = find_goalie_record(home_goalie["playerId"])
      away_goalie = find_starting_goalie("awayTeam")
      away_goalie_record = find_goalie_record(away_goalie["playerId"])
      goalie_images = get_goalie_images(home_goalie, away_goalie)
      officials = NhlApi.officials(game_id)
      scratches = NhlApi.scratches(game_id)

      main_post = format_main_post(@feed, home_goalie, home_goalie_record, away_goalie, away_goalie_record)
      reply_post = format_reply_post(officials, scratches)

      main_post_key = "game_start_#{game_id}"
      RodTheBot::Post.perform_async(main_post, main_post_key)
      RodTheBot::Post.perform_in(1.minute, reply_post, "game_start_reply_#{game_id}", main_post_key, nil, goalie_images)
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

    def format_main_post(feed, home_goalie, home_goalie_record, away_goalie, away_goalie_record)
      <<~POST
        🚦 It's puck drop at #{feed["venue"]["default"]} for #{feed["awayTeam"]["name"]["default"]} at #{feed["homeTeam"]["name"]["default"]}!
        
        Starting Goalies:
        #{feed["homeTeam"]["abbrev"]}: ##{home_goalie["sweaterNumber"]} #{home_goalie["name"]["default"]} #{home_goalie_record}
        #{feed["awayTeam"]["abbrev"]}: ##{away_goalie["sweaterNumber"]} #{away_goalie["name"]["default"]} #{away_goalie_record}
      POST
    end

    def format_reply_post(officials, scratches)
      post = <<~POST
        Officials:

        Referees: #{officials[:referees].join(", ")}
        Lines: #{officials[:linesmen].join(", ")}

      POST
      post += "\nScratches:\n\n#{scratches}\n" if scratches
      post
    end

    def get_goalie_images(home_goalie, away_goalie)
      home_goalie_image = NhlApi.fetch_player_landing_feed(home_goalie["playerId"])["headshot"]
      away_goalie_image = NhlApi.fetch_player_landing_feed(away_goalie["playerId"])["headshot"]
      [home_goalie_image, away_goalie_image]
    end
  end
end
