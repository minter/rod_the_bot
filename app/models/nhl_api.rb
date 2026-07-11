class NhlApi
  include HTTParty

  base_uri "https://api-web.nhle.com/v1"

  class << self
    def officials(game_id)
      right_rail = Nhl::GameClient.right_rail(game_id)
      officials_data = right_rail&.dig("gameInfo")
      return {referees: [], linesmen: []} unless officials_data

      {
        referees: (officials_data["referees"] || []).map { |ref| ref["default"] },
        linesmen: (officials_data["linesmen"] || []).map { |linesman| linesman["default"] }
      }
    end

    def scratches(game_id)
      boxscore = Nhl::GameClient.boxscore(game_id)
      game_data = Nhl::GameClient.right_rail(game_id)
      game_info = game_data&.dig("gameInfo")
      return nil unless game_info

      away_team = boxscore.dig("awayTeam", "abbrev")
      home_team = boxscore.dig("homeTeam", "abbrev")
      return nil unless away_team && home_team

      scratches_data = {}
      ["awayTeam", "homeTeam"].each do |team|
        team_info = game_info[team]
        next unless team_info

        team_scratches = team_info["scratches"] || []
        formatted_scratches = team_scratches.filter_map do |player|
          first_name = player.dig("firstName", "default") || ""
          last_name = player.dig("lastName", "default") || ""
          "#{first_name[0]}. #{last_name}" if first_name.present? && last_name.present?
        end
        scratches_data[team] = formatted_scratches
      end

      return nil if scratches_data["homeTeam"]&.count.to_i > 6 || scratches_data["awayTeam"]&.count.to_i > 6

      away_scratches = (scratches_data["awayTeam"] && scratches_data["awayTeam"].empty?) ? "None" : scratches_data["awayTeam"]&.join(", ") || "None"
      home_scratches = (scratches_data["homeTeam"] && scratches_data["homeTeam"].empty?) ? "None" : scratches_data["homeTeam"]&.join(", ") || "None"

      "#{away_team}: #{away_scratches}\n#{home_team}: #{home_scratches}"
    end

    def splits(game_id)
      splits = Nhl::GameClient.right_rail(game_id)["teamGameStats"]
      splits.each_with_object({}) do |split, result|
        category = split["category"].to_sym
        result[category] = {
          away: format_value(split["awayValue"], category),
          home: format_value(split["homeValue"], category)
        }
      end
    end

    def game_rosters(game_id)
      feed = Nhl::GameClient.play_by_play(game_id)
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

    def opponent_team_id(game_id)
      feed = Nhl::GameClient.landing(game_id)
      return nil unless feed

      your_team_id = ENV["NHL_TEAM_ID"].to_i
      home_id = feed.dig("homeTeam", "id")
      away_id = feed.dig("awayTeam", "id")

      return nil unless home_id && away_id

      (home_id.to_i == your_team_id) ? away_id.to_i : home_id.to_i
    end

    private

    def get(path, options = {})
      response = super
      raise Nhl::RequestError, "API request failed: #{response.code}" unless response.success?

      response.parsed_response
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
      raise Nhl::RequestError, "Network error fetching #{path}: #{e.class} - #{e.message}"
    end

    def format_value(value, category)
      case category
      when :powerPlayPctg, :faceoffWinningPctg
        "#{(value.to_f * 100).round(1)}%"
      else
        value
      end
    end

    def symbolize_keys(hash)
      hash.each_with_object({}) do |(key, value), result|
        new_key = key.to_sym
        new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
        result[new_key] = new_value
      end
    end

    def clean_player_data(player)
      player[:firstName] = player[:firstName][:default]
      player[:lastName] = player[:lastName][:default]
      player[:fullName] = "#{player[:firstName]} #{player[:lastName]}"
      player[:birthCity] = player[:birthCity][:default] || player[:birthCity].values.first if player[:birthCity]
      player[:birthStateProvince] = player[:birthStateProvince][:default] || player[:birthStateProvince]&.values&.first if player[:birthStateProvince]
      player[:name_number] = "##{player[:sweaterNumber]} #{player[:fullName]}"
      player
    end
  end

end
