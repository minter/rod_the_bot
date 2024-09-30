module RodTheBot
  class EndOfPeriodWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter

    attr_reader :feed, :game_final

    def perform(game_id, play)
      @feed = NhlApi.fetch_pbp_feed(game_id)
      @game_final = feed["plays"].any? { |play| play["typeDescKey"] == "game-end" }
      return if game_final
      return if play["periodDescriptor"]["periodType"] == "SO"

      home = feed.fetch("homeTeam", {})
      away = feed.fetch("awayTeam", {})
      period_descriptor = play.fetch("periodDescriptor", {})

      end_of_period_post = format_post(home, away, period_descriptor)

      RodTheBot::Post.perform_async(end_of_period_post)
      RodTheBot::EndOfPeriodStatsWorker.perform_in(60, game_id, period_descriptor.fetch("number", 1))
    end

    private

    def format_post(home, away, period_descriptor)
      period_number = period_descriptor.fetch("number", 1)
      period_name = format_period_name(period_number)

      <<~POST
        🛑 That's the end of the #{period_name}!

        #{away.fetch("name", {}).fetch("default", "")} - #{away.fetch("score", 0)} 
        #{home.fetch("name", {}).fetch("default", "")} - #{home.fetch("score", 0)}

        Shots on goal after the #{period_name}:

        #{away.fetch("name", {}).fetch("default", "")}: #{away.fetch("sog", 0)}
        #{home.fetch("name", {}).fetch("default", "")}: #{home.fetch("sog", 0)}
      POST
    end
  end
end
