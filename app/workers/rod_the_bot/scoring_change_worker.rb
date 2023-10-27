module RodTheBot
  class ScoringChangeWorker
    include Sidekiq::Worker

    def perform(game_id, play_id, original_play)
      @feed = HTTParty.get("https://statsapi.web.nhl.com/api/v1/game/#{game_id}/feed/live")
      @play = nil
      @feed["liveData"]["plays"]["allPlays"].each do |live_play|
        if live_play["about"]["eventId"].to_i == play_id.to_i
          @play = live_play
          break
        end
      end

      # If nothing has changed on this scoring play, exit
      return if @play["players"] == original_play["players"]

      post = <<~POST
        🔔 Scoring Change

        The #{@play["team"]["name"]} goal at #{@play["about"]["periodTime"]} of the #{@play["about"]["ordinalNum"]} period now reads:

      POST
      goal = @play["players"].shift
      post += "🚨 #{goal["player"]["fullName"]} (#{goal["seasonTotal"]})\n"

      if @play["players"].empty?
        post += "🍎 Unassisted\n"
      else
        while (assist = @play["players"].shift)
          next unless assist["playerType"] == "Assist"

          post += "🍎 #{assist["player"]["fullName"]} (#{assist["seasonTotal"]})\n"
        end
      end
      RodTheBot::Post.perform_async(post)
    end
  end
end
