module RodTheBot
  class PostseasonSeriesWorker
    include Sidekiq::Worker

    def perform
      carousel = HTTParty.get("https://api-web.nhle.com/v1/playoff-series/carousel/20232024/")
      rounds = carousel["rounds"]
      current_round = carousel["currentRound"]
      current_series = rounds.find { |round| round["roundNumber"] == current_round }
      format_series(current_series)
    end

    private

    def format_series(current_series)
      post = "📋 Here are the playoff matchups for the #{current_series["roundLabel"].tr("-", " ").titlecase}:\n\n"
      current_series["series"].each do |series|
        post += "#{series["topSeed"]["abbrev"]} #{series["topSeed"]["wins"]} - #{series["bottomSeed"]["abbrev"]} #{series["bottomSeed"]["wins"]}\n\n"
      end
      post
    end
  end
end
