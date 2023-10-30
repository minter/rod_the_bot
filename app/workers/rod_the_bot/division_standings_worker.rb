module RodTheBot
  class DivisionStandingsWorker
    include Sidekiq::Worker

    def perform(team_id)
      # Get the team's division ID
      team = HTTParty.get("https://statsapi.web.nhl.com/api/v1/teams/#{team_id}").parsed_response["teams"][0]
      division_id = team["division"]["id"]

      # Start post
      post = "📋 Here are the current standings for the #{team["division"]["name"]} division:\n\n"

      # Get the standings for the team's division
      standings = HTTParty.get("https://statsapi.web.nhl.com/api/v1/standings/byDivision?division=#{division_id}").parsed_response["records"][0]["teamRecords"]

      # Sort the standings by points from highest to lowest
      standings.sort_by! { |team| -team["points"] }

      # Print the team abbreviation, position, and points for each team in the standings
      standings.each_with_index do |team, index|
        team_data = HTTParty.get("https://statsapi.web.nhl.com/api/v1/teams/#{team["team"]["id"]}").parsed_response["teams"][0]
        post += "#{index + 1}. #{team_data["abbreviation"]}: #{team["points"]} pts (#{team["gamesPlayed"]} GP)\n"
      end

      RodTheBot::Post.perform_async(post)
    end
  end
end
