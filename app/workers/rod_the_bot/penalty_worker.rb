module RodTheBot
  class PenaltyWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    SEVERITY = {
      "MIN" => "Minor",
      "MAJ" => "Major",
      "MIS" => "Misconduct",
      "GMIS" => "Game Misconduct",
      "MATCH" => "Match"
    }.freeze

    def perform(game_id, play_id)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      @play = @feed["plays"].find { |play| play["eventId"].to_i == play_id.to_i }
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

      players = build_players(@feed)

      post = if players[@play["details"]["committedByPlayerId"]][:team_id] == ENV["NHL_TEAM_ID"].to_i
        "🙃 #{@your_team["name"]["default"]} Penalty\n\n"
      else
        "🤩 #{@their_team["name"]["default"]} Penalty!\n\n"
      end

      post += <<~POST
        #{players[@play["details"]["committedByPlayerId"]][:name]} - #{@play["details"]["descKey"].tr("-", " ").titlecase}
        
        That's a #{@play["details"]["duration"]} minute #{SEVERITY[@play["details"]["typeCode"]]} penalty at #{@play["timeInPeriod"]} of the #{ordinalize(@play["period"])} Period
      POST

      RodTheBot::Post.perform_async(post)
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
