module RodTheBot
  class YesterdaysScoresWorker
    include Sidekiq::Worker

    def perform
      scores = NhlApi.fetch_scores
      scores_post = format_scores(scores)
      post_scores(scores_post)
    end

    private

    def format_scores(yesterday_scores)
      return "🙌 Final scores from last night's games:\n\nNo games scheduled\n" if yesterday_scores.empty?

      scores = yesterday_scores.map { |game| format_game_score(game) }
      "🙌 Final scores from last night's games:\n\n#{scores.join("\n")}\n"
    end

    def format_game_score(game)
      home_team, visitor_team = game.values_at("homeTeam", "awayTeam")
      score_text = "#{visitor_team["abbrev"]} #{visitor_team["score"]} : #{home_team["score"]} #{home_team["abbrev"]}"

      score_text << format_overtime(game["periodDescriptor"])
      score_text << format_series_status(visitor_team["abbrev"], home_team["abbrev"]) if NhlApi.postseason?

      score_text
    end

    def format_overtime(period_descriptor)
      case period_descriptor["periodType"]
      when "SO" then " (SO)"
      when "OT"
        (period_descriptor["number"].to_i >= 5) ? " (#{period_descriptor["number"].to_i - 3}OT)" : " (OT)"
      else ""
      end
    end

    def format_series_status(visitor_abbrev, home_abbrev)
      matchup = find_series_matchup(visitor_abbrev, home_abbrev)
      return "" unless matchup

      top_seed, bottom_seed = matchup.values_at("topSeed", "bottomSeed")
      series_length = matchup["neededToWin"]

      if [top_seed["wins"], bottom_seed["wins"]].max == series_length
        winner = (top_seed["wins"] == series_length) ? top_seed : bottom_seed
        loser = (winner == top_seed) ? bottom_seed : top_seed
        " (#{winner["abbrev"]} wins #{winner["wins"]}-#{loser["wins"]})"
      elsif top_seed["wins"] == bottom_seed["wins"]
        " (Series tied #{top_seed["wins"]}-#{bottom_seed["wins"]})"
      else
        leader = (top_seed["wins"] > bottom_seed["wins"]) ? top_seed : bottom_seed
        " (#{leader["abbrev"]} leads #{leader["wins"]}-#{((leader == top_seed) ? bottom_seed : top_seed)["wins"]})"
      end
    end

    def find_series_matchup(team1, team2)
      response = NhlApi.fetch_postseason_carousel
      return unless response&.dig("rounds")

      response["rounds"].each do |round|
        matchup = round["series"].find do |series|
          [series["bottomSeed"]["abbrev"], series["topSeed"]["abbrev"]].sort == [team1, team2].sort
        end
        return matchup if matchup
      end
      nil
    end

    def post_scores(scores_post)
      RodTheBot::Post.perform_async(scores_post)
    end
  end
end
