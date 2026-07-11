module RodTheBot
  class UpcomingMilestonesWorker
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper

    def perform
      # Skip preseason - stats don't count
      return if Nhl::SeasonCalendar.preseason?

      team_id = ENV["NHL_TEAM_ID"].to_i
      game_type = Nhl::SeasonCalendar.postseason? ? 3 : 2
      season_type = Nhl::SeasonCalendar.postseason? ? "Playoffs" : "Regular Season"

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
      roster = Nhl::Roster.for(ENV["NHL_TEAM_ABBREVIATION"])
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

      PostThread.enqueue(milestone_chunks, key: base_key)
    end

    def split_milestones_into_chunks(milestones, season_type)
      # Header for first chunk - only show season type for playoffs
      header = if season_type == "Playoffs"
        "🎯 Upcoming Milestones (#{season_type}):\n\n"
      else
        "🎯 Upcoming Milestones:\n\n"
      end
      PostThread.split_lines(milestones.map { |milestone| format_milestone_line(milestone) }, header: header)
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
