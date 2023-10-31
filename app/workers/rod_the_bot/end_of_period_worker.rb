module RodTheBot
  class EndOfPeriodStatsWorker
    include Sidekiq::Worker

    def perform(game_id, period_number)
      @feed = HTTParty.get("https://statsapi.web.nhl.com/api/v1/game/#{game_id}/feed/live")
      return if @feed["gameData"]["status"]["detailedState"] == "Final"

      @home = @feed["liveData"]["linescore"]["teams"]["home"]
      @visitor = @feed["liveData"]["linescore"]["teams"]["away"]
      @your_team = (@home["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i) ? @home : @visitor
      @your_team_status = (@your_team["team"]["id"] == @home["team"]["id"]) ? "home" : "away"
      @home_code = @feed["gameData"]["teams"]["home"]["abbreviation"]
      @visitor_code = @feed["gameData"]["teams"]["away"]["abbreviation"]

      end_of_period_post = <<~POST
        🛑 That's the end of the #{period_number} period!

        #{@visitor["team"]["name"]} - #{@visitor["goals"]} 
        #{@home["team"]["name"]} - #{@home["goals"]}

        Shots on goal after the #{period_number} period:

        #{@visitor["team"]["name"]}: #{@visitor["shotsOnGoal"]}
        #{@home["team"]["name"]}: #{@home["shotsOnGoal"]}
      POST

      RodTheBot::Post.perform_async(end_of_period_post)
      RodTheBot::EndOfPeriodStatsWorker.perform_async(game_id, period_number)
    end
  end
end
