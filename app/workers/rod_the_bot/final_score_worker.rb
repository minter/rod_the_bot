module RodTheBot
  class FinalScoreWorker
    include Sidekiq::Worker

    attr_reader :feed

    def perform(game_id)
      @feed = NhlApi.fetch_boxscore_feed(game_id)
      home = feed.fetch("homeTeam", {})
      visitor = feed.fetch("awayTeam", {})
      home_team_is_yours = home.fetch("id", "").to_i == ENV["NHL_TEAM_ID"].to_i
      modifier = if feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "SO"
        " (SO)"
      elsif feed.fetch("periodDescriptor", {}).fetch("periodType", "") == "OT"
        (feed["periodDescriptor"]["number"].to_i >= 5) ? " (#{feed["periodDescriptor"]["number"].to_i - 3}OT)" : " (OT)"
      end

      post = format_post(home, visitor, modifier, home_team_is_yours)

      RodTheBot::Post.perform_async(post)
      RodTheBot::EndOfPeriodStatsWorker.perform_async(game_id, "")
    end

    private

    def format_post(home, visitor, modifier, home_team_is_yours)
      home_name = home.dig("name", "default") || ""
      visitor_name = visitor.dig("name", "default") || ""
      home_score = home.fetch("score", 0)
      visitor_score = visitor.fetch("score", 0)

      post = <<~POST
        Final Score#{modifier}:

        #{visitor_name} - #{visitor_score} 
        #{home_name} - #{home_score}

        Shots on goal:

        #{visitor_name}: #{visitor.fetch("sog", 0)}
        #{home_name}: #{home.fetch("sog", 0)}
      POST

      if ENV["WIN_CELEBRATION"].present?
        home_team_won = home_score > visitor_score
        your_team_won = home_team_is_yours ? home_team_won : !home_team_won
        post = "#{ENV["WIN_CELEBRATION"]}\n\n#{post}" if your_team_won
      end

      post
    end
  end
end
