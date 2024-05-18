module RodTheBot
  class YesterdaysScoresWorker
    include Sidekiq::Worker
    include Seasons

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
      if game["periodDescriptor"]["periodType"] == "OT"
        score_text += (game["periodDescriptor"]["number"].to_i >= 5) ? " (#{game["periodDescriptor"]["number"].to_i - 3}OT)" : " (OT)"
      end

      if (matchup = series_find(visitor_team["abbrev"], home_team["abbrev"]))
        series_length = matchup["neededToWin"]
        score_text += if matchup["bottomSeed"]["wins"] == series_length || matchup["topSeed"]["wins"] == series_length
          if matchup["bottomSeed"]["wins"] == series_length
            " (#{matchup["bottomSeed"]["abbrev"]} wins #{matchup["bottomSeed"]["wins"]}-#{matchup["topSeed"]["wins"]})"
          else
            " (#{matchup["topSeed"]["abbrev"]} wins #{matchup["topSeed"]["wins"]}-#{matchup["bottomSeed"]["wins"]})"
          end
        elsif matchup["bottomSeed"]["wins"] == matchup["topSeed"]["wins"]
          " (Series tied #{matchup["bottomSeed"]["wins"]}-#{matchup["topSeed"]["wins"]})"
        elsif matchup["bottomSeed"]["wins"] > matchup["topSeed"]["wins"]
          " (#{matchup["bottomSeed"]["abbrev"]} leads #{matchup["bottomSeed"]["wins"]}-#{matchup["topSeed"]["wins"]})"
        else
          " (#{matchup["topSeed"]["abbrev"]} leads #{matchup["topSeed"]["wins"]}-#{matchup["bottomSeed"]["wins"]})"
        end
      end
      score_text
    end

    def series_find(your_team, their_team)
      response = HTTParty.get("https://api-web.nhle.com/v1/playoff-series/carousel/#{current_season}/")

      response["rounds"].each do |round|
        matchup = round["series"].find { |series| (series["bottomSeed"]["abbrev"] == your_team && series["topSeed"]["abbrev"] == their_team) || (series["topSeed"]["abbrev"] == your_team && series["bottomSeed"]["abbrev"] == their_team) }
        return matchup if matchup
      end
    end

    def post_scores(scores_post)
      RodTheBot::Post.perform_async(scores_post)
    end
  end
end
