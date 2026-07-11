class NhlApi
  include HTTParty

  base_uri "https://api-web.nhle.com/v1"

  class << self
    def fetch_team_schedule(date: Time.now.strftime("%Y-%m-%d"))
      Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      Rails.cache.fetch("team_schedule_#{date}", expires_in: 12.hours) do
        get("/club-schedule/#{ENV["NHL_TEAM_ABBREVIATION"]}/week/#{date}")
      end
    end

    def fetch_roster(team_abbreviation)
      get("/roster/#{team_abbreviation}/current")
    end

    def fetch_standings
      Rails.cache.fetch("standings", expires_in: 8.hours) do
        get("/standings/now")
      end
    end

    def playoff_seed_labels
      standings = fetch_standings
      return {} unless standings && standings["standings"]

      standings["standings"].each_with_object({}) do |team, map|
        abbrev = team.dig("teamAbbrev", "default")
        next unless abbrev

        wildcard = team["wildcardSequence"].to_i
        if wildcard > 0
          map[abbrev] = "WC#{wildcard}"
        else
          div = team["divisionAbbrev"]
          seq = team["divisionSequence"]
          map[abbrev] = "#{div}#{seq}" if div && seq
        end
      end
    end

    def fetch_scores(date: Date.yesterday.strftime("%Y-%m-%d"))
      Rails.cache.fetch("scores_#{date}", expires_in: 18.hours) do
        response = get("/score/#{date}")
        games = response["games"] || []
        games.find_all { |game| game["gameDate"] == date }
      end
    end

    def fetch_postseason_carousel
      get("/playoff-series/carousel/#{Nhl::SeasonCalendar.current_season}/")
    rescue Nhl::RequestError
      nil
    end

    def fetch_league_schedule(date: Time.now.strftime("%Y-%m-%d"))
      Rails.cache.fetch("league_schedule_#{date}", expires_in: 3.hours) do
        get("/schedule/#{date}")
      end
    end

    def todays_game(date: Time.now.strftime("%Y-%m-%d"))
      schedule = fetch_team_schedule(date: date)
      games = schedule["games"] || []
      games.find { |game| game["gameDate"] == date }
    end

    def roster(team_abbreviation)
      Rails.cache.fetch("team_roster_#{team_abbreviation}", expires_in: 5.hours) do
        roster_data = fetch_roster(team_abbreviation)
        players = {}

        %w[forwards defensemen goalies].each do |position_group|
          roster_data[position_group].each do |player|
            player_data = symbolize_keys(player)
            players[player_data[:id]] = clean_player_data(player_data)
          end
        end

        players
      end
    end

    def teams
      Rails.cache.fetch("teams", expires_in: 30.days) do
        teams = {}
        response = HTTParty.get("https://api.nhle.com/stats/rest/en/team")
        raise Nhl::RequestError, "API request failed: #{response.code}" unless response.success?

        response.parsed_response["data"].each do |team|
          team_data = symbolize_keys(team)
          teams[team_data[:id]] = team_data
        end
        teams
      end
    end

    def team_standings(team_abbreviation)
      team = fetch_standings["standings"].find { |t| t["teamAbbrev"]["default"] == team_abbreviation }

      return nil unless team

      {
        division_name: team["divisionName"],
        division_rank: team["divisionSequence"],
        points: team["points"],
        wins: team["wins"],
        losses: team["losses"],
        ot: team["otLosses"],
        team_name: team["teamName"]["default"],
        season_id: team["seasonId"]
      }
    end

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

    def fetch_draft_picks(year)
      get("/draft/picks/#{year}/all")
    end

    def fetch_draft_rankings(year)
      Rails.cache.fetch("draft_rankings_#{year}", expires_in: 24.hours) do
        {
          north_american_skaters: get("/draft/rankings/#{year}/1")["rankings"],
          international_skaters: get("/draft/rankings/#{year}/2")["rankings"],
          north_american_goalies: get("/draft/rankings/#{year}/3")["rankings"],
          international_goalies: get("/draft/rankings/#{year}/4")["rankings"]
        }
      end
    end

    def fetch_player_content(player_id)
      Rails.cache.fetch("player_content_#{player_id}", expires_in: 8.hours) do
        response = HTTParty.get("https://forge-dapi.d3.nhle.com/v2/content/en-us/players?tags.slug=playerid-#{player_id}")
        raise Nhl::RequestError, "API request failed: #{response.code}" unless response.success?
        response.parsed_response
      end
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

    def get_player_career_stats(player_id)
      Rails.cache.fetch("player_career_stats_#{player_id}", expires_in: 1.hour) do
        response = HTTParty.get("https://api.nhle.com/stats/rest/en/skater/stats?cayenneExp=playerId=#{player_id}")
        response.success? ? response.parsed_response : {}
      end
    end

    def get_player_game_log(player_id, limit = 10)
      Rails.cache.fetch("player_game_log_#{player_id}_#{limit}_#{Date.current}", expires_in: 4.hours) do
        season = current_season
        game_type = postseason? ? 3 : 2
        # Use api-web endpoint documented for game logs
        path = "/player/#{player_id}/game-log/#{season}/#{game_type}"
        data = get(path)["gameLog"] || []
        # api-web returns most-recent first; trim to limit
        data.first(limit)
      end
    end

    def get_goalie_game_log(player_id, limit = 10)
      Rails.cache.fetch("goalie_game_log_#{player_id}_#{limit}_#{Date.current}", expires_in: 4.hours) do
        season = current_season
        game_type = postseason? ? 3 : 2
        # Same api-web endpoint serves goalies as well
        path = "/player/#{player_id}/game-log/#{season}/#{game_type}"
        data = get(path)["gameLog"] || []
        data.first(limit)
      end
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
