module RodTheBot
  class PeriodStartWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    def perform(game_id, period_number)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      home = @feed["homeTeam"]
      away = @feed["awayTeam"]

      post = <<~POST
        🎬 It's time to start the #{ordinalize(period_number)} period at #{@feed["venue"]["default"]}!

        We're ready for another puck drop between the #{away["name"]["default"]} and the #{home["name"]["default"]}!
      POST

      RodTheBot::Post.perform_async(post)
    end
  end
end
