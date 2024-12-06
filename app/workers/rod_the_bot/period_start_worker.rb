module RodTheBot
  class PeriodStartWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter

    attr_reader :feed

    def perform(game_id, play)
      @feed = NhlApi.fetch_pbp_feed(game_id)
      home = feed.fetch("homeTeam", {})
      away = feed.fetch("awayTeam", {})

      # Skip posting the start of the shootout
      return if play["periodDescriptor"]["periodType"] == "SO"

      period_descriptor = play.fetch("periodDescriptor", {})
      if period_descriptor.fetch("number") == 1
        # Use the start of game worker instead of the start of period worker
        GameStartWorker.perform_async(game_id)
      else
        post = format_post(period_descriptor, home, away)
        RodTheBot::Post.perform_async(post)
      end
    end

    def format_post(period_descriptor, home, away)
      period_number = period_descriptor.fetch("number", 1)
      period_name = format_period_name(period_number)

      <<~POST
        🎬 It's time to start the #{period_name} at #{feed.fetch("venue", {}).fetch("default", "")}!

        We're ready for another puck drop between the #{away.fetch("commonName", {}).fetch("default", "")} and the #{home.fetch("commonName", {}).fetch("default", "")}!
      POST
    end
  end
end
