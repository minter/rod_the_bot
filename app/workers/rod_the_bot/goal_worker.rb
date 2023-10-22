module RodTheBot
  class GoalWorker
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
      @your_team = if home["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        home
      else
        away
      end

      return if @play["about"]["periodType"] == "SHOOTOUT"

      home = @feed["gameData"]["teams"]["home"]
      away = @feed["gameData"]["teams"]["away"]

      type = (@play["result"]["strength"]["code"] == "EVEN") ? "" : @play["result"]["strength"]["name"] + " "
      type += "Empty Net " if @play["result"]["emptyNet"]

      post = if @play["team"]["id"] == ENV["NHL_TEAM_ID"].to_i
        "🎉 #{@your_team["name"]} #{type}GOOOOOOOAL! 🎉\n\n"
      else
        "👎 #{@play["team"]["name"]} #{type}Goal 👎\n\n"
      end

      goal = @play["players"].shift
      post += "🚨 # #{goal["player"]["fullName"]} (#{goal["seasonTotal"]})\n"

      if @play["players"].empty?
        post += "🍎 Unassisted\n"
      else
        while (assist = @play["players"].shift)
          next unless assist["playerType"] == "Assist"

          post += "🍎 #{assist["player"]["fullName"]} (#{assist["seasonTotal"]})\n"
        end
      end
      post += "⏱️  #{@play["about"]["periodTime"]} #{@play["about"]["ordinalNum"]} Period\n\n"
      post += "#{away["abbreviation"]} #{@play["about"]["goals"]["away"]} - #{home["abbreviation"]} #{@play["about"]["goals"]["home"]}"
      RodTheBot::Post.perform_async(post)
      RodTheBot::ScoringChangeWorker.perform_in(600, game_id, play_id, @play)
    end
  end
end
