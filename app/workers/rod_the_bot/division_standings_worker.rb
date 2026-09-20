module RodTheBot
  class DivisionStandingsWorker
    include Sidekiq::Worker

    def perform
      return if Nhl::SeasonCalendar.preseason?

      standings = Nhl::StandingsClient.current_standings
      return if standings.empty?

      my_division = Nhl::StandingsClient.team(ENV["NHL_TEAM_ABBREVIATION"])&.dig(:division_name)
      unless my_division
        Rails.logger.warn "DivisionStandingsWorker: No division for #{ENV["NHL_TEAM_ABBREVIATION"]} in current standings. Skipping."
        return
      end

      division_teams = sort_teams_in_division(standings, my_division)
      return if division_teams.empty?

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
        clinch_indicator = team["clinchIndicator"] + "-" if team["clinchIndicator"].present?
        point_percentage = sprintf("%.3f", team["pointPctg"].to_f)
        post += "#{index + 1}. #{clinch_indicator}#{team["teamAbbrev"]["default"]}: #{team["points"]} pts (#{point_percentage}%)\n"
      end
      post
    end
  end
end
