module RodTheBot
  class UpcomingMilestonesWorker
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper

    def perform
      # Skip preseason - stats don't count
      return if NhlApi.preseason?

      team_id = ENV["NHL_TEAM_ID"].to_i
      game_type = NhlApi.postseason? ? 3 : 2
      season_type = NhlApi.postseason? ? "Playoffs" : "Regular Season"

      # Get currently rostered players
      current_roster = get_current_roster_player_ids
      return if current_roster.empty?

      # Get upcoming milestones for rostered players only
      upcoming_milestones = get_upcoming_milestones(team_id, game_type, current_roster)

      return if upcoming_milestones.empty?

      # Split milestones into multiple posts if needed
      post_milestones_in_threads(upcoming_milestones, season_type)
    end

    private

    def get_current_roster_player_ids
      # Get current team roster
      roster = NhlApi.roster(ENV["NHL_TEAM_ABBREVIATION"])
      roster.keys.map(&:to_s)
    end

    def get_upcoming_milestones(team_id, game_type, current_roster)
      # Get skater milestones
      skater_milestones = fetch_skater_milestones
      team_skater_milestones = skater_milestones["data"].select { |m|
        m["currentTeamId"] == team_id &&
          m["gameTypeId"] == game_type &&
          current_roster.include?(m["playerId"].to_s)
      }

      # Get goalie milestones
      goalie_milestones = fetch_goalie_milestones
      team_goalie_milestones = goalie_milestones["data"].select { |m|
        m["currentTeamId"] == team_id &&
          m["gameTypeId"] == game_type &&
          current_roster.include?(m["playerId"].to_s)
      }

      # Filter for close milestones (realistically achievable within 1-2 games)
      all_milestones = team_skater_milestones + team_goalie_milestones
      all_milestones.select { |milestone|
        remaining = milestone["milestoneAmount"] - get_current_value(milestone)
        max_remaining = get_max_remaining_for_milestone_type(milestone["milestone"])
        remaining <= max_remaining && remaining > 0
      }
    end

    def fetch_skater_milestones
      Rails.cache.fetch("skater_milestones_#{Date.current}", expires_in: 24.hours) do
        response = HTTParty.get("https://api.nhle.com/stats/rest/en/milestones/skaters")
        response.success? ? response.parsed_response : {}
      end
    end

    def fetch_goalie_milestones
      Rails.cache.fetch("goalie_milestones_#{Date.current}", expires_in: 24.hours) do
        response = HTTParty.get("https://api.nhle.com/stats/rest/en/milestones/goalies")
        response.success? ? response.parsed_response : {}
      end
    end

    def get_current_value(milestone)
      case milestone["milestone"]
      when "Goals" then milestone["goals"]
      when "Assists" then milestone["assists"]
      when "Points" then milestone["points"]
      when "Games Played" then milestone["gamesPlayed"]
      when "Wins" then milestone["wins"]
      when "Shutouts" then milestone["so"]
      when "Minutes Played" then milestone["toiMinutes"]
      else 0
      end
    end

    def get_max_remaining_for_milestone_type(milestone_type)
      case milestone_type
      when "Goals" then 3
      when "Points" then 6
      when "Assists" then 5
      when "Wins" then 2
      when "Shutouts" then 1
      when "Games Played" then 2
      when "Minutes Played" then 0  # Skip minutes milestones
      else 0
      end
    end

    def post_milestones_in_threads(milestones, season_type)
      # Sort by urgency (closest first)
      milestones.sort_by! { |m| m["milestoneAmount"] - get_current_value(m) }

      # Generate unique keys for threading
      current_date = Time.now.strftime("%Y%m%d")
      base_key = "upcoming_milestones:#{current_date}"

      # Split milestones into chunks that fit within character limit
      milestone_chunks = split_milestones_into_chunks(milestones, season_type)

      return if milestone_chunks.empty?

      # Post first chunk as main post
      first_chunk = milestone_chunks.first
      first_key = "#{base_key}:1"
      RodTheBot::Post.perform_async(first_chunk, first_key)

      # Post remaining chunks as replies
      milestone_chunks[1..].each_with_index do |chunk, index|
        chunk_key = "#{base_key}:#{index + 2}"
        parent_key = (index == 0) ? first_key : "#{base_key}:#{index + 1}"
        RodTheBot::Post.perform_in((index + 1).seconds, chunk, chunk_key, parent_key)
      end
    end

    def split_milestones_into_chunks(milestones, season_type)
      chunks = []
      current_chunk = []

      # Account for team hashtags that will be added by Post worker
      hashtags = ENV["TEAM_HASHTAGS"] || ""
      hashtag_length = hashtags.empty? ? 0 : hashtags.length + 1 # +1 for newline
      max_content_length = 300 - hashtag_length

      # Header for first chunk - only show season type for playoffs
      header = if season_type == "Playoffs"
        "🎯 Upcoming Milestones (#{season_type}):\n\n"
      else
        "🎯 Upcoming Milestones:\n\n"
      end
      current_chunk_size = header.length
      current_chunk << header

      milestones.each do |milestone|
        milestone_line = format_milestone_line(milestone)
        line_length = milestone_line.length # Already includes newline

        # If adding this milestone would exceed the limit, start a new chunk
        if current_chunk_size + line_length > max_content_length && !current_chunk.empty?
          # Finish current chunk (no extra newline - Post worker will add it)
          chunks << current_chunk.join

          # Start new chunk
          current_chunk = []
          current_chunk_size = 0
        end

        current_chunk << milestone_line
        current_chunk_size += line_length
      end

      # Add final chunk if it has content (no extra newline - Post worker will add it)
      if !current_chunk.empty?
        chunks << current_chunk.join
      end

      chunks
    end

    def format_milestone_line(milestone)
      player_name = milestone["playerFullName"]
      milestone_type = milestone["milestone"]
      current_value = get_current_value(milestone)
      target_value = milestone["milestoneAmount"]
      remaining = target_value - current_value

      urgency = get_urgency_emoji(milestone_type, remaining)

      display_type = case milestone_type
      when "Games Played" then "game"
      when "Goals" then "goal"
      when "Assists" then "assist"
      when "Points" then "point"
      when "Wins" then "win"
      when "Shutouts" then "shutout"
      else milestone_type.downcase.singularize
      end

      "#{urgency} #{player_name}: #{pluralize(remaining, display_type)} away from #{target_value}\n"
    end

    def get_urgency_emoji(milestone_type, remaining)
      case milestone_type
      when "Goals", "Assists", "Points", "Games Played"
        # Skater milestones - more frequent, lower urgency thresholds
        case remaining
        when 1 then "🔥"      # Very close
        when 2..3 then "⚡"   # Close
        else "📈"             # Approaching
        end
      when "Wins"
        # Wins - happen frequently, can be more generous
        case remaining
        when 1 then "🔥"      # Very close
        when 2 then "⚡"      # Close
        else "📈"             # Approaching
        end
      when "Shutouts"
        # Shutouts - very rare, only alert when very close
        case remaining
        when 1 then "🔥"      # Very close (only alert when 1 away)
        else "📈"             # Approaching (2+ away)
        end
      else
        # Default for any other milestone types
        case remaining
        when 1..2 then "🔥"
        when 3..4 then "⚡"
        else "📈"
        end
      end
    end
  end
end
