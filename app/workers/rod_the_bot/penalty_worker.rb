module RodTheBot
  class PenaltyWorker
    include Sidekiq::Worker

    def perform(game_id, play_id)
      @feed = HTTParty.get("https://statsapi.web.nhl.com/api/v1/game/#{game_id}/feed/live")
      @play = nil
      @feed["liveData"]["plays"]["allPlays"].each do |live_play|
        if live_play["about"]["eventId"].to_i == play_id.to_i
          @play = live_play
          break
        end
      end

      home = @game["games"].first["teams"]["home"]
      away = @game["games"].first["teams"]["away"]
      @your_team = if home["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        home
      else
        away
      end

      home = @feed["gameData"]["teams"]["home"]
      away = @feed["gameData"]["teams"]["away"]

      post = if @play["team"]["id"] == ENV["NHL_TEAM_ID"].to_i
        "🙃 #{@your_team["name"]} Penalty 🙃\n\n"
      else
        "🤩 #{@play["team"]["name"]} Penalty! 🤩\n\n"
      end

      post += <<~POST
        #{@play["result"]["description"]}
        
        That's a #{@play["result"]["penaltyMinutes"]} minute #{@play["result"]["penaltySeverity"].downcase} penalty at #{@play["about"]["periodTime"]} of the #{@play["about"]["ordinalNum"]} Period

        #{away["abbreviation"]} #{@play["about"]["goals"]["away"]} - #{home["abbreviation"]} #{@play["about"]["goals"]["home"]}
      POST

      RodTheBot::Post.perform_async(post)
    end
  end
end
