module RodTheBot
  class FinalScoreWorker
    include Sidekiq::Worker

    attr_reader :feed

    def perform(game_id)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/boxscore")
      home = feed.fetch("homeTeam", {})
      visitor = feed.fetch("awayTeam", {})
      home_team_is_yours = home.fetch("id", "").to_i == ENV["NHL_TEAM_ID"].to_i
      modifier = if feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "SO"
        " (SO)"
      elsif feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "OT"
        " (OT)"
      end

      post = format_post(home, visitor, modifier, home_team_is_yours)

      RodTheBot::Post.perform_async(post)
      RodTheBot::EndOfPeriodStatsWorker.perform_async(game_id, "")
    end

    private

    def format_post(home, visitor, modifier, home_team_is_yours)
      post = <<~POST
        Final Score#{modifier}:

        #{visitor.fetch("name", {}).fetch("default", "")} - #{visitor.fetch("score", 0)} 
        #{home.fetch("name", {}).fetch("default", "")} - #{home.fetch("score", 0)}

        Shots on goal:

        #{visitor.fetch("name", {}).fetch("default", "")}: #{visitor.fetch("sog", 0)}
        #{home.fetch("name", {}).fetch("default", "")}: #{home.fetch("sog", 0)}
      POST

      if ENV["WIN_CELEBRATION"].present? && (home_team_is_yours && home.fetch("score", 0) > visitor.fetch("score", 0)) || (!home_team_is_yours && home.fetch("score", 0) < visitor.fetch("score", 0))
        post = "#{ENV["WIN_CELEBRATION"]}\n\n#{post}"
      end

      post
    end
  end
end
