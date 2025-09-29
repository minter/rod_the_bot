module RodTheBot
  class GoalieChangeWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    def perform(game_id, play)
      return unless play["details"] && play["details"]["goalieInNetId"]

      @feed = NhlApi.fetch_pbp_feed(game_id)
      @play = play

      goalie_id = play["details"]["goalieInNetId"]
      event_team = play["details"]["eventOwnerTeamId"]

      home = @feed["homeTeam"]
      away = @feed["awayTeam"]

      # Determine which team's goalie changed (defending team)
      defending_team_id = (event_team == home["id"]) ? away["id"] : home["id"]
      defending_team = (defending_team_id == home["id"]) ? home : away

      # Check if this is actually a goalie change
      current_goalie = REDIS.get("game:#{game_id}:current_goalie:#{defending_team_id}")

      if goalie_id != current_goalie && goalie_id.present? && current_goalie.present?
        # GOALIE CHANGE DETECTED!
        new_goalie = get_goalie_info(goalie_id)
        return if new_goalie.nil?

        post = build_post(defending_team, new_goalie)
        headshot = get_goalie_headshot(goalie_id)
        images = headshot ? [headshot] : []

        RodTheBot::Post.perform_async(post, nil, nil, nil, images)

        # Update cache with new goalie
        REDIS.set("game:#{game_id}:current_goalie:#{defending_team_id}", goalie_id, ex: 28800)

        Rails.logger.info "GoalieChangeWorker: Detected goalie change for team #{defending_team_id}, new goalie: #{new_goalie[:name]} (##{new_goalie[:number]})"
      end
    end

    private

    def build_post(team, goalie)
      city_name = team["placeName"]["default"]      # "Florida"
      team_nickname = team["commonName"]["default"] # "Panthers"

      <<~POST
        🥅 Goaltending change for #{city_name}!

        Now in goal for the #{team_nickname}, ##{goalie[:number]} #{goalie[:name]}
      POST
    end

    def get_goalie_info(goalie_id)
      # Get goalie info from current game roster
      players = build_players(@feed)
      goalie = players[goalie_id]

      return nil if goalie.nil?

      {
        name: goalie[:name],
        number: goalie[:number],
        team_id: goalie[:team_id]
      }
    end

    def get_goalie_headshot(goalie_id)
      goalie_feed = NhlApi.fetch_player_landing_feed(goalie_id)
      goalie_feed&.dig("headshot")
    rescue => e
      Rails.logger.warn "GoalieChangeWorker: Could not fetch headshot for player #{goalie_id}: #{e.message}"
      nil
    end

    def build_players(feed)
      players = {}
      feed["rosterSpots"].each do |player|
        players[player["playerId"]] = {
          team_id: player["teamId"],
          number: player["sweaterNumber"],
          name: player["firstName"]["default"] + " " + player["lastName"]["default"]
        }
      end
      players
    end
  end
end
