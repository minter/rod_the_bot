module RodTheBot
  class YesterdaysScoresWorker
    include Sidekiq::Worker

    def perform
      # Get the scores for all games last night
      yesterday = Date.yesterday.strftime("%Y-%m-%d")
      scores_post = "🙌 Final scores from last night's games:\n\n"
      response = HTTParty.get("https://api-web.nhle.com/v1/score/#{yesterday}")["games"]
      yesterday_scores = response.find_all { |game| game["gameDate"] == yesterday }
      scores = []
      if yesterday_scores.empty?
        scores_post += "No games scheduled\n"
      else
        yesterday_scores.each do |game|
          home_team = game["homeTeam"]
          home_score = home_team["score"]
          visitor_team = game["awayTeam"]
          visitor_score = visitor_team["score"]
          score_text = "#{visitor_team["abbrev"]} #{visitor_score} : #{home_score} #{home_team["abbrev"]}"
          score_text += " (SO)" if game["periodDescriptor"]["periodType"] == "SO"
          score_text += " (OT)" if game["periodDescriptor"]["periodType"] == "OT"
          scores.push(score_text)
        end

        # Save the scores in a post
        scores_post += scores.join("\n") + "\n"
      end

      # Post the scores to your social media account
      RodTheBot::Post.perform_async(scores_post)
    end
  end
end
