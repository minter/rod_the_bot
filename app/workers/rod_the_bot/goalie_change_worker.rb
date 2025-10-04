module RodTheBot
  class GoalieChangeWorker
    include Sidekiq::Worker
    include RodTheBot::PlayerFormatter
    include ActiveSupport::Inflector

    def perform(game_id, play)
      return unless play["details"] && play["details"]["goalieInNetId"]

      @feed = NhlApi.fetch_pbp_feed(game_id)
      @play = play

      goalie_id = play["details"]["goalieInNetId"].to_s  # Ensure string for comparison
      event_team = play["details"]["eventOwnerTeamId"]

      home = @feed["homeTeam"]
      away = @feed["awayTeam"]

      # Determine which team's goalie this shot was against (defending team)
      defending_team_id = (event_team == home["id"]) ? away["id"] : home["id"]
      defending_team = (defending_team_id == home["id"]) ? home : away

      # Get current cached goalie for this team
      current_goalie = REDIS.get("game:#{game_id}:current_goalie:#{defending_team_id}")

      # If no cached goalie (GameStartWorker didn't run or cache expired), initialize from game state
      if current_goalie.blank?
        Rails.logger.info "GoalieChangeWorker: No cached goalie for team #{defending_team_id}. Initializing cache from current game state."
        REDIS.set("game:#{game_id}:current_goalie:#{defending_team_id}", goalie_id, ex: 28800)
        return  # Don't post on cache initialization
      end

      Rails.logger.debug "GoalieChangeWorker: Team #{defending_team_id}, cached: #{current_goalie}, current: #{goalie_id}, event: #{play["eventId"]}"

      # Only detect change if we have a cached value and it's different
      if current_goalie.present? && goalie_id.present? && goalie_id != current_goalie

        # Safety check: Look at recent plays to confirm this is actually a new goalie
        # Skip if this goalie has been active in recent plays (prevents false positives from stale cache)
        recent_plays = @feed["plays"].select { |p|
          p["details"] &&
            p["details"]["goalieInNetId"] == play["details"]["goalieInNetId"] &&
            p["eventId"] < play["eventId"]
        }.last(5)  # Check last 5 plays with this goalie

        if recent_plays.length >= 3
          Rails.logger.info "GoalieChangeWorker: Skipping false positive - #{goalie_id} has been active recently. Updating cache silently."
          REDIS.set("game:#{game_id}:current_goalie:#{defending_team_id}", goalie_id, ex: 28800)
          return
        end
        # GOALIE CHANGE DETECTED!

        # Use atomic operation to prevent race conditions - only proceed if we can claim this change
        change_lock_key = "game:#{game_id}:goalie_change_lock:#{defending_team_id}:#{goalie_id}"
        if REDIS.set(change_lock_key, "claimed", nx: true, ex: 300)  # 5 minute lock
          new_goalie = get_goalie_info(play["details"]["goalieInNetId"])  # Use original integer for API calls
          return if new_goalie.nil?

          # Update cache with new goalie
          REDIS.set("game:#{game_id}:current_goalie:#{defending_team_id}", goalie_id, ex: 28800)

          post = build_post(defending_team, new_goalie)
          headshot = get_goalie_headshot(play["details"]["goalieInNetId"])  # Use original integer
          images = headshot ? [headshot] : []

          RodTheBot::Post.perform_async(post, nil, nil, nil, images)

          Rails.logger.info "GoalieChangeWorker: Posted goalie change for team #{defending_team_id}, #{current_goalie} → #{goalie_id} (#{new_goalie[:name]} ##{new_goalie[:number]})"
        else
          Rails.logger.debug "GoalieChangeWorker: Change already claimed by another worker. Team #{defending_team_id}, #{current_goalie} → #{goalie_id}"
        end
      else
        Rails.logger.debug "GoalieChangeWorker: No change detected. Team #{defending_team_id}, cached: #{current_goalie}, current: #{goalie_id}"
      end
    end

    private

    def build_post(team, goalie)
      city_name = team["placeName"]["default"]      # "Florida"
      team_nickname = team["commonName"]["default"] # "Panthers"

      # Format goalie name with jersey number using consistent format  
      goalie_name = format_player_with_components(goalie[:number], goalie[:first_name], goalie[:last_name])

      <<~POST
        🥅 Goaltending change for #{city_name}!

        Now in goal for the #{team_nickname}, #{goalie_name}
      POST
    end

    def get_goalie_info(goalie_id)
      # Get goalie info from current game roster
      players = build_players(@feed)
      goalie = players[goalie_id]

      return nil if goalie.nil?

      {
        first_name: goalie[:first_name],
        last_name: goalie[:last_name],
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
          first_name: player["firstName"]["default"],
          last_name: player["lastName"]["default"]
        }
      end
      players
    end
  end
end
