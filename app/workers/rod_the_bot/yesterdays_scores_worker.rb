module RodTheBot
  class YesterdaysScoresWorker
    include Sidekiq::Worker

    def perform
      # Get the scores for all games last night
      yesterday = Date.yesterday
      scores_post = "🙌 Final scores from last night's games:\n\n"
      response = HTTParty.get("https://statsapi.web.nhl.com/api/v1/schedule?date=#{yesterday.strftime("%Y-%m-%d")}&expand=schedule.linescore")
      if response["dates"].empty? || response["dates"][0]["games"].empty?
        scores_post += "No games scheduled\n"
      else
        scores = response["dates"][0]["games"].map do |game|
          home_team = HTTParty.get("https://statsapi.web.nhl.com#{game["teams"]["home"]["team"]["link"]}").parsed_response["teams"][0]["abbreviation"]
          home_score = game["teams"]["home"]["score"]
          visitor_team = HTTParty.get("https://statsapi.web.nhl.com#{game["teams"]["away"]["team"]["link"]}").parsed_response["teams"][0]["abbreviation"]
          visitor_score = game["teams"]["away"]["score"]
          score = "#{visitor_team} #{visitor_score} : #{home_score} #{home_team}"
          score += " (SO)" if game["linescore"]["currentPeriodOrdinal"] == "SO"
          score += " (OT)" if game["linescore"]["currentPeriodOrdinal"] == "OT"
          score
        end

        # Save the scores in a post
        scores_post += scores.join("\n") + "\n"
      end

      # Post the scores to your social media account
      RodTheBot::Post.perform_async(scores_post)
    end
  end
end
