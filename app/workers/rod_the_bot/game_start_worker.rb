module RodTheBot
  class GameStartWorker
    include Sidekiq::Worker
    include RodTheBot::PlayerFormatter
    include PlayerImageHelper

    def perform(game_id)
      @feed = NhlApi.fetch_pbp_feed(game_id)
      home_goalie = find_starting_goalie("homeTeam")
      home_goalie_record = find_goalie_record(home_goalie["playerId"])
      away_goalie = find_starting_goalie("awayTeam")
      away_goalie_record = find_goalie_record(away_goalie["playerId"])
      goalie_images = get_goalie_images(home_goalie, away_goalie)

      # Cache starting goalies for goalie change detection
      home_team_id = @feed["homeTeam"]["id"]
      away_team_id = @feed["awayTeam"]["id"]
      REDIS.set("game:#{game_id}:current_goalie:#{home_team_id}", home_goalie["playerId"].to_s, ex: 28800) # 8 hours
      REDIS.set("game:#{game_id}:current_goalie:#{away_team_id}", away_goalie["playerId"].to_s, ex: 28800)

      officials = NhlApi.officials(game_id)
      scratches = NhlApi.scratches(game_id)

      main_post = format_main_post(@feed, home_goalie, home_goalie_record, away_goalie, away_goalie_record)
      reply_post = format_reply_post(officials, scratches)

      # Add timestamp to keys to ensure uniqueness
      current_date = Time.now.strftime("%Y%m%d")
      main_post_key = "game_start_#{game_id}:#{current_date}"
      RodTheBot::Post.perform_async(main_post, main_post_key, nil, nil, goalie_images)
      RodTheBot::Post.perform_in(1.minute, reply_post, "game_start_reply_#{game_id}:#{current_date}", main_post_key)

      # Store pre-game career stats for milestone detection (skip in preseason)
      RodTheBot::PregameStatsWorker.perform_async(game_id) unless NhlApi.preseason?
    end

    private

    def find_starting_goalie(team)
      goalies = @feed.dig("summary", "iceSurface", team, "goalies")
      if goalies&.any?
        goalies.first
      else
        Rails.logger.warn "GameStartWorker: No goalies found for #{team} in game feed"
        # Return a fallback goalie structure
        {
          "playerId" => nil,
          "sweaterNumber" => "?",
          "name" => {"default" => "Unknown Goalie"}
        }
      end
    end

    def find_goalie_record(player_id)
      return "(Stats unavailable)" if player_id.nil?

      # In preseason, goalies often don't have current season stats yet
      return "(Preseason - Stats unavailable)" if NhlApi.preseason?

      season = (@feed["gameType"] == 3) ? "playoffs" : "regularSeason"
      player = NhlApi.fetch_player_landing_feed(player_id)

      # Add error handling for missing or malformed data
      unless player && player["featuredStats"]
        Rails.logger.warn "GameStartWorker: Missing featuredStats for player #{player_id}"
        return "(Stats unavailable)"
      end

      unless player["featuredStats"][season]
        Rails.logger.warn "GameStartWorker: Missing season '#{season}' in featuredStats for player #{player_id}"
        return "(Stats unavailable)"
      end

      unless player["featuredStats"][season]["subSeason"]
        Rails.logger.warn "GameStartWorker: Missing subSeason in featuredStats[#{season}] for player #{player_id}"
        return "(Stats unavailable)"
      end

      stats = player["featuredStats"][season]["subSeason"]

      # Check if required stats fields exist
      unless stats["wins"] && stats["losses"] && stats["otLosses"] && stats["goalsAgainstAvg"] && stats["savePctg"]
        Rails.logger.warn "GameStartWorker: Missing required stat fields for player #{player_id}"
        return "(Stats unavailable)"
      end

      "(#{stats["wins"]}-#{stats["losses"]}-#{stats["otLosses"]}, #{sprintf("%.2f", stats["goalsAgainstAvg"].round(2))} GAA, #{sprintf("%.3f", stats["savePctg"].round(3))} SV%)"
    end

    def format_main_post(feed, home_goalie, home_goalie_record, away_goalie, away_goalie_record)
      # Get game roster data for consistent formatting
      players = NhlApi.game_rosters(feed["id"])

      # Format goalie names with jersey numbers using consistent format
      home_goalie_name = format_player_from_roster(players, home_goalie["playerId"])
      away_goalie_name = format_player_from_roster(players, away_goalie["playerId"])

      <<~POST
        🚦 It's puck drop at #{feed["venue"]["default"]} for #{feed["awayTeam"]["commonName"]["default"]} at #{feed["homeTeam"]["commonName"]["default"]}!
        
        Starting Goalies:

        #{feed["homeTeam"]["abbrev"]}: #{home_goalie_name} #{home_goalie_record}
        
        #{feed["awayTeam"]["abbrev"]}: #{away_goalie_name} #{away_goalie_record}
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
      home_goalie_image = fetch_player_headshot(home_goalie["playerId"])
      away_goalie_image = fetch_player_headshot(away_goalie["playerId"])

      [home_goalie_image, away_goalie_image]
    end
  end
end
