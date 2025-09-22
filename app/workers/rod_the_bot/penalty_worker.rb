module RodTheBot
  class PenaltyWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter

    SEVERITY = {
      "MIN" => "Minor",
      "MAJ" => "Major",
      "MIS" => "Misconduct",
      "GMIS" => "Game Misconduct",
      "MATCH" => "Match",
      "BEN" => "Minor",
      "PS" => "Penalty Shot"
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

      penalized_player_id = @play["details"]["committedByPlayerId"] || @play["details"]["servedByPlayerId"]
      penalized_player = players[@play["details"]["committedByPlayerId"]] || players[@play["details"]["servedByPlayerId"]]
      
      # Handle case where player is not found in roster (common in preseason)
      if penalized_player.nil?
        Rails.logger.warn "PenaltyWorker: Player #{penalized_player_id} not found in roster for game #{game_id}"
        return
      end
      
      post = if penalized_player[:team_id] == ENV["NHL_TEAM_ID"].to_i
        "🙃 #{@your_team["commonName"]["default"]} Penalty\n\n"
      else
        "🤩 #{@their_team["commonName"]["default"]} Penalty!\n\n"
      end

      period_name = format_period_name(@play["periodDescriptor"]["number"])

      post += if play["details"]["typeCode"] == "BEN"
        served_by_player = players[@play["details"]["servedByPlayerId"]]
        served_by_name = served_by_player&.dig(:name) || "Unknown Player"
        <<~POST
          Bench Minor - #{@play["details"]["descKey"].tr("-", " ").titlecase}
          Penalty is served by #{served_by_name}

          That's a #{@play["details"]["duration"]} minute penalty at #{@play["timeInPeriod"]} of the #{period_name}
        POST
      elsif play["details"]["typeCode"] == "PS"
        committed_by_player = players[@play["details"]["committedByPlayerId"]]
        committed_by_name = committed_by_player&.dig(:name) || "Unknown Player"
        <<~POST
          #{committed_by_name} - #{@play["details"]["descKey"].sub(/^ps-/, "").tr("-", " ").titlecase}
          
          That's a penalty shot awarded at #{@play["timeInPeriod"]} of the #{period_name}
        POST

      else
        committed_by_player = players[@play["details"]["committedByPlayerId"]]
        committed_by_name = committed_by_player&.dig(:name) || "Unknown Player"
        <<~POST
          #{committed_by_name} - #{@play["details"]["descKey"].tr("-", " ").titlecase}
          
          That's a #{@play["details"]["duration"]} minute #{SEVERITY[@play["details"]["typeCode"]]} penalty at #{@play["timeInPeriod"]} of the #{period_name}
        POST
      end

      penalized_player_landing_feed = NhlApi.fetch_player_landing_feed(penalized_player_id)

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
  end
end
