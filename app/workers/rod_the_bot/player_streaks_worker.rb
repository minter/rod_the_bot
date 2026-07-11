module RodTheBot
  class PlayerStreaksWorker
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper

    def perform
      # Skip preseason - stats don't count
      return if Nhl::SeasonCalendar.preseason?

      season_type = Nhl::SeasonCalendar.postseason? ? "Playoffs" : "Regular Season"

      # Get currently rostered players
      current_roster = get_current_roster_player_ids
      return if current_roster.empty?

      # Get active player streaks
      streaks = analyze_player_streaks(current_roster)
      return if streaks.empty?

      # Post streaks as a separate thread
      post_streaks_in_thread(streaks, season_type)
    end

    private

    def get_current_roster_player_ids
      # Get current team roster (uses cached roster method)
      roster.keys.map(&:to_s)
    end

    def analyze_player_streaks(current_roster)
      goalie_ids = roster.filter_map { |id, player| id.to_s if player[:position] == "G" }
      analyzer.analyze(player_ids: current_roster, goalie_ids: goalie_ids).map do |streak|
        streak.merge(player_name: get_player_name_from_id(streak[:player_id])).except(:player_id)
      end
    end

    def roster
      @roster ||= Nhl::Roster.for(ENV["NHL_TEAM_ABBREVIATION"])
    end

    def analyzer
      @analyzer ||= PlayerStreaks::Analyzer.new(
        game_log: ->(player_id, limit) { Nhl::PlayerClient.game_log(player_id, limit: limit) },
        season: Nhl::SeasonCalendar.current_season,
        game_type: Nhl::SeasonCalendar.postseason? ? 3 : 2,
        minimum_length: ENV.fetch("STREAK_MIN_LENGTH", "3")
      )
    end

    def get_player_name_from_id(player_id)
      player_directory.resolve(player_id).name_with_number
    end

    def player_directory
      @player_directory ||= Nhl::PlayerDirectory.for_team(ENV["NHL_TEAM_ABBREVIATION"])
    end

    def post_streaks_in_thread(streaks, season_type)
      return if streaks.empty?

      # Sort by streak length (longest first)
      streaks.sort_by! { |s| -s[:length] }

      # Generate unique keys for threading
      current_date = Time.now.strftime("%Y%m%d")
      base_key = "player_streaks:#{current_date}"

      # Split streaks into chunks that fit within character limit
      streak_chunks = formatter.chunks(streaks, season_type: season_type)

      return if streak_chunks.empty?

      PostThread.enqueue(streak_chunks, key: base_key)
    end

    def formatter
      @formatter ||= PlayerStreaks::Formatter.new
    end
  end
end
