module RodTheBot
  class PenaltyWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter
    include RodTheBot::PlayerFormatter

    SEVERITY = {
      "MIN" => "Minor",
      "MAJ" => "Major",
      "MIS" => "Misconduct",
      "GMIS" => "Game Misconduct",
      "MATCH" => "Match",
      "BEN" => "Minor",
      "PS" => "Penalty Shot"
    }.freeze

    PENALTY_NAMES = {
      # Common penalties with better formatting
      "delaying-game" => "Delay Of Game",
      "too-many-men-on-the-ice" => "Too Many Men",
      "cross-checking" => "Cross-Checking",
      "high-sticking" => "High-Sticking",
      "high-sticking-double-minor" => "High-Sticking (Double Minor)",
      "checking-from-behind" => "Checking from Behind",
      "abuse-of-officials" => "Abuse of Officials",
      "unsportsmanlike-conduct" => "Unsportsmanlike Conduct",
      "unsportsmanlike-conduct-bench" => "Unsportsmanlike Conduct (Bench)",
      "goalie-leave-crease" => "Goaltender Left Crease",
      "goalie-participation-beyond-center" => "Goaltender Beyond Center Line",
      "illegal-check-to-head" => "Illegal Check to the Head",
      "playing-without-a-helmet" => "Playing Without a Helmet",
      "throwing-equipment" => "Throwing Equipment",

      # Specific delay of game penalties
      "delaying-game-puck-over-glass" => "Delay of Game - Puck over Glass",
      "delaying-game-face-off-violation" => "Delay of Game - Face-off Violation",
      "delaying-game-bench-face-off-violation" => "Delay of Game - Bench Face-off Violation",
      "delaying-game-equipment" => "Delay of Game - Equipment",
      "delaying-game-smothering-puck" => "Delay of Game - Smothering Puck",
      "delaying-game-unsuccessful-challenge" => "Delay of Game - Unsuccessful Challenge",
      "delaying-game-bench" => "Delay of Game (Bench)",

      # Penalty shot penalties (remove ps- prefix in helper method)
      "covering-puck-in-crease" => "Covering Puck in Crease",
      "goalkeeper-displaced-net" => "Goalkeeper Displaced Net",
      "holding-on-breakaway" => "Holding on Breakaway",
      "hooking-on-breakaway" => "Hooking on Breakaway",
      "net-displaced" => "Net Displaced",
      "slash-on-breakaway" => "Slashing on Breakaway",
      "throwing-object-at-puck" => "Throwing Object at Puck",
      "tripping-on-breakaway" => "Tripping on Breakaway",

      # Specific variations
      "roughing-removing-opponents-helmet" => "Roughing - Removing Opponent's Helmet",
      "spearing-double-minor" => "Spearing (Double Minor)",
      "interference-goalkeeper" => "Goaltender Interference",
      "interference-bench" => "Interference (Bench)",
      "holding-the-stick" => "Holding the Stick",
      "puck-thrown-forward-goalkeeper" => "Puck Thrown Forward by Goalkeeper",
      "instigator-misconduct" => "Instigator Misconduct",
      "game-misconduct-head-coach" => "Game Misconduct (Head Coach)"
    }.freeze

    def perform(game_id, play)
      @feed = NhlApi.fetch_pbp_feed(game_id)
      return if play.blank?

      @play = NhlApi.fetch_play(game_id, play["eventId"])
      return if @play.nil?

      # Check if descKey is still "minor" and re-queue if so
      if @play["details"]["descKey"] == "minor"
        self.class.perform_in(10.seconds, game_id, play) # Re-queue the job after 10 seconds
        return
      end

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

      # Always prioritize the player who committed the penalty for display and headshot
      committed_player_id = @play["details"]["committedByPlayerId"]
      served_player_id = @play["details"]["servedByPlayerId"]

      # Use committed player for main penalty info, fallback to served player if needed
      main_player_id = committed_player_id || served_player_id
      main_player = players[main_player_id]

      # Handle case where player is not found in roster (common in preseason)
      if main_player.nil?
        Rails.logger.warn "PenaltyWorker: Player #{main_player_id} not found in roster for game #{game_id}"
        return
      end

      post = if main_player[:team_id] == ENV["NHL_TEAM_ID"].to_i
        "🙃 #{@your_team["commonName"]["default"]} Penalty\n\n"
      else
        "🤩 #{@their_team["commonName"]["default"]} Penalty!\n\n"
      end

      period_name = format_period_name(@play["periodDescriptor"]["number"])

      post += if play["details"]["typeCode"] == "BEN"
        served_by_player_name = format_player_from_roster(players, served_player_id)
        <<~POST
          Bench Minor - #{format_penalty_name(@play["details"]["descKey"])}
          Penalty is served by #{served_by_player_name}

          That's a #{@play["details"]["duration"]} minute penalty at #{@play["timeInPeriod"]} of the #{period_name}
        POST
      elsif play["details"]["typeCode"] == "PS"
        main_player_name = format_player_from_roster(players, committed_player_id)
        <<~POST
          #{main_player_name} - #{format_penalty_name(@play["details"]["descKey"].sub(/^ps-/, ""))}
          
          That's a penalty shot awarded at #{@play["timeInPeriod"]} of the #{period_name}
        POST
      else
        main_player_name = format_player_from_roster(players, committed_player_id)
        penalty_message = <<~POST
          #{main_player_name} - #{format_penalty_name(@play["details"]["descKey"])}
          
          That's a #{@play["details"]["duration"]} minute #{SEVERITY[@play["details"]["typeCode"]]} penalty at #{@play["timeInPeriod"]} of the #{period_name}
        POST

        # Add serving note if someone else is serving the penalty
        if served_player_id && served_player_id != committed_player_id
          served_by_player_name = format_player_from_roster(players, served_player_id)
          penalty_message += "\n(Penalty served by #{served_by_player_name})"
        end

        penalty_message
      end

      # Always use the main player (committed player) for headshot
      penalized_player_landing_feed = NhlApi.fetch_player_landing_feed(main_player_id)

      # Safely fetch headshot - may be nil in preseason
      headshot = penalized_player_landing_feed&.dig("headshot")
      images = headshot ? [headshot] : []
      RodTheBot::Post.perform_async(post, nil, nil, nil, images)
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

    def format_penalty_name(desc_key)
      # Use custom mapping first, fallback to default formatting
      PENALTY_NAMES[desc_key] || desc_key.tr("-", " ").titlecase
    end
  end
end
