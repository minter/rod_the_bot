module RodTheBot
  class DivisionStandingsWorker
    include Sidekiq::Worker

    def perform
      standings = NhlApi.fetch_standings["standings"]
      return if NhlApi.preseason?(standings.first["seasonId"])
      my_division = NhlApi.team_standings(ENV["NHL_TEAM_ABBREVIATION"])[:division_name]
      division_teams = sort_teams_in_division(standings, my_division)
      post = format_standings(my_division, division_teams)
      RodTheBot::Post.perform_async(post)
    end

    private

    def sort_teams_in_division(standings, my_division)
      standings
        .select { |team| team["divisionName"] == my_division }
        .sort_by { |team| [-team["pointPctg"].to_f, -team["points"].to_i, -team["gamesPlayed"].to_i] }
    end

    def format_standings(my_division, division_teams)
      post = "📋 Here are the current standings for the #{my_division} division (by PT%):\n\n"
      division_teams.each_with_index do |team, index|
        point_percentage = sprintf("%.3f", team["pointPctg"].to_f)
        post += "#{index + 1}. #{team["teamAbbrev"]["default"]}: #{team["points"]} pts (#{point_percentage}%)\n"
      end
      post
    end
  end
end
