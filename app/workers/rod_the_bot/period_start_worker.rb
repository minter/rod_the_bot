module RodTheBot
  class PeriodStartWorker
    include Sidekiq::Worker

    def perform(game_id, period_number)
      @feed = HTTParty.get("https://statsapi.web.nhl.com/api/v1/game/#{game_id}/feed/live")
      @home = @feed["liveData"]["linescore"]["teams"]["home"]["team"]
      @visitor = @feed["liveData"]["linescore"]["teams"]["away"]["team"]

      post = <<~POST
        🎬 It's time to start the #{period_number} period at #{@feed["gameData"]["venue"]["name"]}!

        We're ready for another puck drop between the #{@visitor["name"]} and the #{@home["name"]}!
      POST

      RodTheBot::Post.perform_async(post)
    end
  end
end
