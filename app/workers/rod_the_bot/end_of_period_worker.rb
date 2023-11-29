module RodTheBot
  class EndOfPeriodWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    attr_reader :feed, :game_final

    def perform(game_id, period_number)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      @game_final = feed["plays"].any? { |play| play["typeDescKey"] == "game-end" }
      return if game_final

      home = feed.fetch("homeTeam", {})
      away = feed.fetch("awayTeam", {})

      end_of_period_post = format_post(home, away, period_number)

      RodTheBot::Post.perform_async(end_of_period_post)
      RodTheBot::EndOfPeriodStatsWorker.perform_async(game_id, ordinalize(period_number))
    end

    private

    def format_post(home, away, period_number)
      <<~POST
        🛑 That's the end of the #{ordinalize(period_number)} period!

        #{away.fetch("name", {}).fetch("default", "")} - #{away.fetch("score", 0)} 
        #{home.fetch("name", {}).fetch("default", "")} - #{home.fetch("score", 0)}

        Shots on goal after the #{ordinalize(period_number)} period:

        #{away.fetch("name", {}).fetch("default", "")}: #{away.fetch("sog", 0)}
        #{home.fetch("name", {}).fetch("default", "")}: #{home.fetch("sog", 0)}
      POST
    end
  end
end
