module RodTheBot
  class YesterdaysScoresWorker
    include Sidekiq::Worker

    def perform
      scores = fetch_yesterdays_scores
      scores_post = format_scores(scores)
      post_scores(scores_post)
    end

    private

    def fetch_yesterdays_scores
      Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      yesterday = Date.yesterday.strftime("%Y-%m-%d")
      response = HTTParty.get("https://api-web.nhle.com/v1/score/#{yesterday}")["games"]
      response.find_all { |game| game["gameDate"] == yesterday }
    end

    def format_scores(yesterday_scores)
      scores_post = "🙌 Final scores from last night's games:\n\n"
      if yesterday_scores.empty?
        scores_post += "No games scheduled\n"
      else
        scores = yesterday_scores.map do |game|
          format_game_score(game)
        end
        scores_post += scores.join("\n") + "\n"
      end
      scores_post
    end

    def format_game_score(game)
      home_team = game["homeTeam"]
      home_score = home_team["score"]
      visitor_team = game["awayTeam"]
      visitor_score = visitor_team["score"]
      score_text = "#{visitor_team["abbrev"]} #{visitor_score} : #{home_score} #{home_team["abbrev"]}"
      score_text += " (SO)" if game["periodDescriptor"]["periodType"] == "SO"
      score_text += " (OT)" if game["periodDescriptor"]["periodType"] == "OT"
      if game["periodDescriptor"]["periodType"] == "OT"
        score_text += (game["periodDescriptor"]["number"].to_i >= 4) ? " (#{game["periodDescriptor"]["number"].to_i - 3}OT)" : " (OT)"
      end
      score_text
    end

    def post_scores(scores_post)
      RodTheBot::Post.perform_async(scores_post)
    end
  end
end
