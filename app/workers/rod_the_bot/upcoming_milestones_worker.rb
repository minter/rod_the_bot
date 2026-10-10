module RodTheBot
  class UpcomingMilestonesWorker
    include Sidekiq::Worker
    include WorkerErrorHandling

    def perform
      # Skip offseason and preseason - stats don't count
      return if Nhl::SeasonCalendar.offseason? || Nhl::SeasonCalendar.preseason?

      playoffs = Nhl::SeasonCalendar.postseason?
      season_type = playoffs ? :playoffs : :regularSeason
      upcoming = Milestones::Upcoming.new(
        career_totals: ->(player_id) { Nhl::PlayerClient.career_totals(player_id, season_type: season_type) }
      )

      entries = Nhl::Roster.for(team_abbreviation).values.flat_map do |player|
        upcoming.for(player[:id], goalie: player[:positionCode] == "G")
      end
      return if entries.empty?

      formatter = Milestones::UpcomingFormatter.new
      lines = entries.sort_by(&:remaining).map do |entry|
        formatter.line(player_directory.resolve(entry.player_id).name_with_number, entry)
      end
      PostThread.enqueue(
        PostThread.split_lines(lines, header: formatter.header(playoffs: playoffs)),
        key: "upcoming_milestones:#{Time.now.strftime("%Y%m%d")}"
      )
    rescue => e
      retry_job(e, operation: "upcoming_milestones")
    end

    private

    def team_abbreviation
      ENV["NHL_TEAM_ABBREVIATION"]
    end

    def player_directory
      @player_directory ||= Nhl::PlayerDirectory.for_team(team_abbreviation)
    end
  end
end
