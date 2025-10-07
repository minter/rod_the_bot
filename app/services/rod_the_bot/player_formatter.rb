module RodTheBot
  module PlayerFormatter
    extend self

    # Format player name consistently as "#xx Firstname Lastname"
    def format_player_name(player_data)
      return "Unknown Player" unless player_data

      # Handle different data structures
      number = extract_number(player_data)
      first_name = extract_first_name(player_data)
      last_name = extract_last_name(player_data)

      return "Unknown Player" if first_name.blank? || last_name.blank?

      "##{number} #{first_name} #{last_name}"
    end

    # Format player name from roster data (used in workers with game rosters)
    def format_player_from_roster(players_hash, player_id)
      player = players_hash[player_id]
      return "Unknown Player" unless player

      number = player[:number] || player["number"] || "?"
      name = player[:name] || player["name"] || "Unknown Player"

      "##{number} #{name}"
    end

    # Format player name when you have separate components
    def format_player_with_components(number, first_name, last_name)
      return "Unknown Player" if first_name.blank? || last_name.blank?

      "##{number || "?"} #{first_name} #{last_name}"
    end

    private

    def extract_number(player_data)
      player_data["sweaterNumber"] ||
        player_data[:number] ||
        player_data["number"] ||
        "?"
    end

    def extract_first_name(player_data)
      if player_data["firstName"].is_a?(Hash)
        player_data["firstName"]["default"]
      else
        player_data["firstName"] || player_data[:firstName]
      end
    end

    def extract_last_name(player_data)
      if player_data["lastName"].is_a?(Hash)
        player_data["lastName"]["default"]
      else
        player_data["lastName"] || player_data[:lastName]
      end
    end
  end
end
