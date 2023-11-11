module RodTheBot
  class DivisionStandingsWorker
    include Sidekiq::Worker

    def perform
      # Get the standings for your team's division
      standings = HTTParty.get("https://api-web.nhle.com/v1/standings/now")["standings"]
      my_team = standings.find { |team| team["teamAbbrev"]["default"] == ENV["NHL_TEAM_ABBREVIATION"] }
      my_division = my_team["divisionName"]
      division_teams = standings.select { |team| team["divisionName"] == my_division }.sort_by { |team| [team["points"], team["gamesPlayed"]] }.reverse

      # Start post
      post = "📋 Here are the current standings for the #{my_division} division:\n\n"

      # Print the team abbreviation, position, and points for each team in the standings
      division_teams.each_with_index do |team, index|
        post += "#{index + 1}. #{team["teamAbbrev"]["default"]}: #{team["points"]} pts (#{team["gamesPlayed"]} GP)\n"
      end

      RodTheBot::Post.perform_async(post)
    end
  end
end
