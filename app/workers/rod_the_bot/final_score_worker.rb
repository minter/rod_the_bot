module RodTheBot
  class FinalScoreWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/boxscore")
      home = @feed["homeTeam"]
      visitor = @feed["awayTeam"]
      home_team_is_yours = home["id"].to_i == ENV["NHL_TEAM_ID"].to_i
      modifier = if @feed["periodDescriptor"]["periodType"] == "SO"
        " (SO)"
      elsif @feed["periodDescriptor"]["periodType"] == "OT"
        " (OT)"
      end

      post = <<~POST
        Final Score#{modifier}:

        #{visitor["name"]["default"]} - #{visitor["score"]} 
        #{home["name"]["default"]} - #{home["score"]}

        Shots on goal:

        #{visitor["name"]["default"]}: #{visitor["sog"]}
        #{home["name"]["default"]}: #{home["sog"]}
      POST

      post = "#{ENV["WIN_CELEBRATION"]}\n\n#{post}" if ENV["WIN_CELEBRATION"].present? && (home_team_is_yours && home["score"] > visitor["score"]) || (!home_team_is_yours && home["score"] < visitor["score"])

      RodTheBot::Post.perform_async(post)
      RodTheBot::EndOfPeriodStatsWorker.perform_async(game_id, "")
    end
  end
end
