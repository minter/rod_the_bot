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
      @play = play
      return if @play.nil?

      home = @feed["homeTeam"]
      away = @feed["awayTeam"]

      if home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        @your_team = home
        @their_team = away
      else
        @your_team = away
        @their_team = home
      end

      return if @feed["plays"].find { |play| play["eventId"] == @play["eventId"] }.blank?

      players = build_players(@feed)

      penalized_player = players[@play["details"]["committedByPlayerId"]] || players[@play["details"]["servedByPlayerId"]]

      post = if penalized_player[:team_id] == ENV["NHL_TEAM_ID"].to_i
        "🙃 #{@your_team["name"]["default"]} Penalty\n\n"
      else
        "🤩 #{@their_team["name"]["default"]} Penalty!\n\n"
      end

      period_name = format_period_name(@play["periodDescriptor"]["number"])

      post += if play["details"]["typeCode"] == "BEN"
        <<~POST
          Bench Minor - #{@play["details"]["descKey"].tr("-", " ").titlecase}
          Penalty is served by #{players[@play["details"]["servedByPlayerId"]][:name]}

          That's a #{@play["details"]["duration"]} minute penalty at #{@play["timeInPeriod"]} of the #{period_name}
        POST
      elsif play["details"]["typeCode"] == "PS"
        <<~POST
          #{players[@play["details"]["committedByPlayerId"]][:name]} - #{@play["details"]["descKey"].sub(/^ps-/, "").tr("-", " ").titlecase}
          
          That's a penalty shot awarded at #{@play["timeInPeriod"]} of the #{period_name}
        POST

      else
        <<~POST
          #{players[@play["details"]["committedByPlayerId"]][:name]} - #{@play["details"]["descKey"].tr("-", " ").titlecase}
          
          That's a #{@play["details"]["duration"]} minute #{SEVERITY[@play["details"]["typeCode"]]} penalty at #{@play["timeInPeriod"]} of the #{period_name}
        POST
      end

      penalized_player_landing_feed = NhlApi.fetch_player_landing_feed(@play["details"]["committedByPlayerId"])

      images = [penalized_player_landing_feed["headshot"]]
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
