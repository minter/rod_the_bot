module RodTheBot
  class FinalScoreWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = HTTParty.get("https://statsapi.web.nhl.com/api/v1/game/#{game_id}/linescore")
      home = @feed["teams"]["home"]
      visitor = @feed["teams"]["away"]
      home_team_is_yours = home["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i
      modifier = if @feed["hasShootout"] == true
        " (SO)"
      elsif @feed["periods"].last["periodType"] == "OVERTIME"
        " (OT)"
      end

      post = <<~POST
        Final Score#{modifier}:

        #{visitor["team"]["name"]} - #{visitor["goals"]} 
        #{home["team"]["name"]} - #{home["goals"]}

        Shots on goal:

        #{visitor["team"]["name"]}: #{visitor["shotsOnGoal"]}
        #{home["team"]["name"]}: #{home["shotsOnGoal"]}
      POST

      post = "#{ENV["WIN_CELEBRATION"]}\n\n#{post}" if ENV["WIN_CELEBRATION"].present? && (home_team_is_yours && home["goals"] > visitor["goals"]) || (!home_team_is_yours && home["goals"] < visitor["goals"])

      RodTheBot::Post.perform_async(post)
    end
  end
end
