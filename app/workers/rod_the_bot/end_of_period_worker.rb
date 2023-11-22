module RodTheBot
  class EndOfPeriodWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    def perform(game_id, period_number)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      @game_final = @feed["plays"].find { |play| play["typeDescKey"] == "game-end" }.present?
      return if @game_final

      home = @feed["homeTeam"]
      away = @feed["awayTeam"]

      end_of_period_post = <<~POST
        🛑 That's the end of the #{ordinalize(period_number)} period!

        #{away["name"]["default"]} - #{away["score"]} 
        #{home["name"]["default"]} - #{home["score"]}

        Shots on goal after the #{ordinalize(period_number)} period:

        #{away["name"]["default"]}: #{away["sog"]}
        #{home["name"]["default"]}: #{home["sog"]}
      POST

      RodTheBot::Post.perform_async(end_of_period_post)
      RodTheBot::EndOfPeriodStatsWorker.perform_async(game_id, ordinalize(period_number))
    end
  end
end
