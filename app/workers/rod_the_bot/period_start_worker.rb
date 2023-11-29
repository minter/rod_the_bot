module RodTheBot
  class PeriodStartWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    attr_reader :feed

    def perform(game_id, period_number)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      home = feed.fetch("homeTeam", {})
      away = feed.fetch("awayTeam", {})

      post = format_post(period_number, home, away)

      RodTheBot::Post.perform_async(post)
    end

    def format_post(period_number, home, away)
      <<~POST
        🎬 It's time to start the #{ordinalize(period_number)} period at #{feed.fetch("venue", {}).fetch("default", "")}!

        We're ready for another puck drop between the #{away.fetch("name", {}).fetch("default", "")} and the #{home.fetch("name", {}).fetch("default", "")}!
      POST
    end
  end
end
