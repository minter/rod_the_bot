module RodTheBot
  class MilestoneCheckerWorker
    include Sidekiq::Worker

    def perform(game_id, play)
      @game_id = game_id

      case play["typeDescKey"]
      when "goal"
        check_goal_milestones(play)
      when "game-end"
        check_goalie_milestones
      end
    end

    private

    def check_goal_milestones(play)
      details = play["details"]
      return unless details
      return unless details["eventOwnerTeamId"].to_i == tracked_team_id
      return unless details["scoringPlayerId"].present?
      return unless player_on_tracked_team?(details["scoringPlayerId"])

      scorer_id = details["scoringPlayerId"]
      enqueue_events(get_player_name(scorer_id), evaluator.scorer(scorer_id))

      %w[assist1PlayerId assist2PlayerId].each do |key|
        player_id = details[key]
        next unless player_id.present? && player_on_tracked_team?(player_id)

        enqueue_events(get_player_name(player_id), evaluator.assister(player_id))
      end
    end

    def get_player_name(player_id)
      player_directory.name_with_number(player_id)
    end

    def check_goalie_milestones
      # Get team goalies from the game feed (use cached feed)
      feed = game_feed
      roster_spots = feed&.dig("rosterSpots") || []
      team_goalies = roster_spots.filter_map do |player|
        identity = player_directory.fetch(player["playerId"])
        identity if identity&.position == "G" && identity.team_id == tracked_team_id
      end

      team_goalies.each do |goalie|
        enqueue_events(goalie.name_with_number, evaluator.goalie(goalie.id))
      end
    end

    def calculate_career_total(player_id, stat_type)
      career_total.for(player_id, stat_type)
    end

    def game_feed
      @game_feed ||= Nhl::GameClient.play_by_play(@game_id)
    end

    def career_total
      @career_total ||= Milestones::CareerTotal.new(game_id: @game_id, feed: method(:game_feed))
    end

    def evaluator
      @evaluator ||= Milestones::Evaluator.new(totals: career_total)
    end

    def formatter
      @formatter ||= Milestones::Formatter.new
    end

    def enqueue_events(player_name, events)
      events.each { |event| RodTheBot::Post.perform_async(formatter.format(player_name, event)) }
    end

    def tracked_team_id
      @tracked_team_id ||= ENV["NHL_TEAM_ID"].to_i
    end

    def game_roster
      player_directory
    end

    def player_directory
      @player_directory ||= Nhl::PlayerDirectory.for_game(@game_id)
    end

    def player_on_tracked_team?(player_id)
      player = game_roster.fetch(player_id)
      return false unless player

      player.team_id == tracked_team_id
    end
  end
end
