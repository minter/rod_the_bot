module RodTheBot
  class GoalieChangeWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    def perform(game_id, play)
      return unless play["details"] && play["details"]["goalieInNetId"]

      @feed = Nhl::GameClient.play_by_play(game_id)
      @play = play

      goalie_id = play["details"]["goalieInNetId"].to_s  # Ensure string for comparison
      event_team = play["details"]["eventOwnerTeamId"]

      home = @feed["homeTeam"]
      away = @feed["awayTeam"]

      # Determine which team's goalie this shot was against (defending team)
      defending_team_id = (event_team == home["id"]) ? away["id"] : home["id"]
      defending_team = (defending_team_id == home["id"]) ? home : away

      result = detector.detect(game_id: game_id, team_id: defending_team_id, goalie_id: goalie_id, event_id: play["eventId"], plays: @feed["plays"])
      if result.status == :changed
          new_goalie = player_directory(game_id).fetch(play["details"]["goalieInNetId"])
          return if new_goalie.nil?
          detector.commit(game_id: game_id, team_id: defending_team_id, goalie_id: goalie_id)

          post = build_post(defending_team, new_goalie)
          headshot = get_goalie_headshot(play["details"]["goalieInNetId"])  # Use original integer
          images = headshot ? [headshot] : []

          RodTheBot::Post.perform_async(post, nil, nil, nil, images)

          Rails.logger.info "GoalieChangeWorker: Posted goalie change for team #{defending_team_id}, #{result.previous_goalie_id} → #{goalie_id} (#{new_goalie.name_with_number})"
      end
    end

    private

    def build_post(team, goalie)
      city_name = team["placeName"]["default"]      # "Florida"
      team_nickname = team["commonName"]["default"] # "Panthers"

      # Format goalie name with jersey number using consistent format
      goalie_name = goalie.name_with_number

      <<~POST
        🥅 Goaltending change for #{city_name}!

        Now in goal for the #{team_nickname}, #{goalie_name}
      POST
    end

    def get_goalie_headshot(goalie_id)
      goalie_feed = Nhl::PlayerClient.landing(goalie_id)
      goalie_feed&.dig("headshot")
    rescue => e
      Rails.logger.warn "GoalieChangeWorker: Could not fetch headshot for player #{goalie_id}: #{e.message}"
      nil
    end

    def player_directory(game_id)
      @player_directory ||= Nhl::PlayerDirectory.for_game(game_id)
    end

    def detector = @detector ||= GoalieChange::Detector.new
  end
end
