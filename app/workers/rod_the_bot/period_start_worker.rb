module RodTheBot
  class PeriodStartWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    attr_reader :feed

    def perform(game_id, play)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      home = feed.fetch("homeTeam", {})
      away = feed.fetch("awayTeam", {})

      period_descriptor = play.fetch("periodDescriptor", {})
      post = format_post(period_descriptor, home, away)

      RodTheBot::Post.perform_async(post)
    end

    def format_post(period_descriptor, home, away)
      period_number = period_descriptor.fetch("number", 1)
      period = (period_descriptor.fetch("periodType") == "REG") ? ordinalize(period_number) : period_descriptor.fetch("periodType")
      <<~POST
        🎬 It's time to start the #{period} period at #{feed.fetch("venue", {}).fetch("default", "")}!

        We're ready for another puck drop between the #{away.fetch("name", {}).fetch("default", "")} and the #{home.fetch("name", {}).fetch("default", "")}!
      POST
    end
  end
end
