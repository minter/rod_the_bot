module RodTheBot
  class PostseasonSeriesWorker
    include Sidekiq::Worker

    def perform
      carousel = NhlApi.fetch_postseason_carousel
      rounds = carousel["rounds"]
      current_round = carousel["currentRound"]
      current_series = fetch_current_series(rounds, current_round)
      post = format_series(current_series)
      RodTheBot::Post.perform_async(post)
    end

    private

    def fetch_current_series(rounds, current_round)
      current_series = rounds.find { |round| round["roundNumber"] == current_round }
      if current_round > 1 && current_series["series"].select { |s| s["bottomSeed"]["wins"] > 0 || s["topSeed"]["wins"] > 0 }.blank?
        # We're past round 1, and no games played in the "current round", so report the previous round
        current_series = rounds.find { |round| round["roundNumber"] == (current_round - 1) }
      end
      current_series
    end

    def format_series(current_series)
      post = "📋 Here are the playoff matchups for the #{current_series["roundLabel"].tr("-", " ").titlecase}:\n\n"
      current_series["series"].each do |series|
        top_seed_won = series["topSeed"]["wins"] == series["neededToWin"]
        bottom_seed_won = series["bottomSeed"]["wins"] == series["neededToWin"]

        trophy_prefix = ""
        trophy_suffix = ""

        if top_seed_won
          trophy_prefix = "🏆 "
        elsif bottom_seed_won
          trophy_suffix = " 🏆"
        end

        post += "#{trophy_prefix}#{series["topSeed"]["abbrev"]} #{series["topSeed"]["wins"]} - #{series["bottomSeed"]["abbrev"]} #{series["bottomSeed"]["wins"]}#{trophy_suffix}\n\n"
      end
      post
    end
  end
end
