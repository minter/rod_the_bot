module RodTheBot
  class GameStartWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = HTTParty.get("https://statsapi.web.nhl.com/api/v1/game/#{game_id}/feed/live")
      home = @feed["gameData"]["teams"]["home"]
      visitor = @feed["gameData"]["teams"]["away"]
      referees = []
      lines = []
      @feed["liveData"]["boxscore"]["officials"].each do |official|
        if official["officialType"] == "Referee"
          referees.push official["official"]["fullName"]
        elsif official["officialType"] == "Linesman"
          lines.push official["official"]["fullName"]
        end
      end

      post = <<~POST
        🚦 We're ready for puck drop at #{@feed["gameData"]["venue"]["name"]}!
        
        #{visitor["name"]} at #{home["name"]} is about to begin!

        Referees: #{referees.join(", ")}
        Lines: #{lines.join(", ")}
      POST
      RodTheBot::Post.perform_async(post)
    end
  end
end
