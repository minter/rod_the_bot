module RodTheBot
  class DivisionStandingsWorker
    include Sidekiq::Worker

    def perform
      standings = fetch_standings
      return if preseason?(standings.first["seasonId"])
      my_division = find_my_division(standings)
      division_teams = sort_teams_in_division(standings, my_division)
      post = format_standings(my_division, division_teams)
      RodTheBot::Post.perform_async(post)
    end

    private

    def fetch_standings
      HTTParty.get("https://api-web.nhle.com/v1/standings/now")["standings"]
    end

    def find_my_division(standings)
      my_team = standings.find { |team| team["teamAbbrev"]["default"] == ENV["NHL_TEAM_ABBREVIATION"] }
      my_team["divisionName"]
    end

    def sort_teams_in_division(standings, my_division)
      standings.select { |team| team["divisionName"] == my_division }.sort_by { |team| [team["pointPctg"], team["points"], team["gamesPlayed"]] }.reverse
    end

    def format_standings(my_division, division_teams)
      post = "📋 Here are the current standings for the #{my_division} division (by PT%):\n\n"
      division_teams.each_with_index do |team, index|
        post += "#{index + 1}. #{team["teamAbbrev"]["default"]}: #{team["points"]} pts (#{sprintf("%.3f", team["pointPctg"].round(3))}%)\n"
      end
      post
    end
  end
end
