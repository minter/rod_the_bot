class NhlApi
  include HTTParty

  base_uri "https://api-web.nhle.com/v1"

  class << self
    def fetch_pbp_feed(game_id)
      get("/gamecenter/#{game_id}/play-by-play")
    end

    def fetch_play(game_id, play_id)
      feed = fetch_pbp_feed(game_id)
      return nil unless feed && feed["plays"].is_a?(Array)

      feed["plays"].find { |play| play["eventId"].to_s == play_id.to_s }
    end

    def fetch_boxscore_feed(game_id)
      get("/gamecenter/#{game_id}/boxscore")
    end

    def fetch_landing_feed(game_id)
      get("/gamecenter/#{game_id}/landing")
    end

    def fetch_player_landing_feed(player_id)
      Rails.cache.fetch("player_landing_feed_#{player_id}", expires_in: 8.hours) do
        get("/player/#{player_id}/landing")
      end
    end

    def fetch_right_rail_feed(game_id)
      get("/gamecenter/#{game_id}/right-rail")
    end

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

    def fetch_scores(date: Date.yesterday.strftime("%Y-%m-%d"))
      Rails.cache.fetch("scores_#{date}", expires_in: 18.hours) do
        response = get("/score/#{date}")["games"]
        response.find_all { |game| game["gameDate"] == date }
      end
    end

    def fetch_postseason_carousel
      get("/playoff-series/carousel/#{current_season}/")
    rescue NhlApi::APIError
      nil
    end

    def fetch_league_schedule(date: Time.now.strftime("%Y-%m-%d"))
      Rails.cache.fetch("league_schedule_#{date}", expires_in: 3.hours) do
        get("/schedule/#{date}")
      end
    end

    def todays_game(date: Time.now.strftime("%Y-%m-%d"))
      fetch_team_schedule(date: date)["games"].find { |game| game["gameDate"] == date }
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
        raise APIError, "API request failed: #{response.code}" unless response.success?

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
      officials_data = fetch_right_rail_feed(game_id)["gameInfo"]
      {
        referees: officials_data["referees"].map { |ref| ref["default"] },
        linesmen: officials_data["linesmen"].map { |linesman| linesman["default"] }
      }
    end

    def scratches(game_id)
      boxscore = fetch_boxscore_feed(game_id)
      game_data = fetch_right_rail_feed(game_id)
      game_info = game_data["gameInfo"]
      away_team = boxscore["awayTeam"]["abbrev"]
      home_team = boxscore["homeTeam"]["abbrev"]

      scratches_data = {}
      ["awayTeam", "homeTeam"].each do |team|
        team_scratches = game_info[team]["scratches"]
        formatted_scratches = team_scratches.map do |player|
          "#{player["firstName"]["default"][0]}. #{player["lastName"]["default"]}"
        end
        scratches_data[team] = formatted_scratches
      end

      return nil if scratches_data["homeTeam"].count > 6 || scratches_data["awayTeam"].count > 6

      away_scratches = scratches_data["awayTeam"].empty? ? "None" : scratches_data["awayTeam"].join(", ")
      home_scratches = scratches_data["homeTeam"].empty? ? "None" : scratches_data["homeTeam"].join(", ")

      "#{away_team}: #{away_scratches}\n#{home_team}: #{home_scratches}"
    end

    def splits(game_id)
      splits = fetch_right_rail_feed(game_id)["teamGameStats"]
      splits.each_with_object({}) do |split, result|
        category = split["category"].to_sym
        result[category] = {
          away: format_value(split["awayValue"], category),
          home: format_value(split["homeValue"], category)
        }
      end
    end

    def game_rosters(game_id)
      feed = fetch_pbp_feed(game_id)
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

    def current_season
      get("/season").last.to_s
    end

    def postseason?
      Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      league_schedule = league_schedule_for_now
      regular_season_end_date = Date.parse(league_schedule["regularSeasonEndDate"])
      Time.zone.today > regular_season_end_date
    end

    def offseason?
      Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      schedule = league_schedule_for_now
      today = Time.zone.today
      pre_season_start_date = Date.parse(schedule["preSeasonStartDate"])
      playoff_end_date = Date.parse(schedule["playoffEndDate"])

      (today < pre_season_start_date || today > playoff_end_date) ||
        (today.between?(pre_season_start_date, playoff_end_date) && schedule["numberOfGames"].zero?)
    end

    def preseason?
      Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      schedule = league_schedule_for_now
      today = Time.zone.today
      pre_season_start_date = Date.parse(schedule["preSeasonStartDate"])
      regular_season_start_date = Date.parse(schedule["regularSeasonStartDate"])

      today >= pre_season_start_date && today < regular_season_start_date
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

    private

    def league_schedule_for_now
      Rails.cache.fetch("league_schedule_now", expires_in: 3.hours) do
        get("/schedule/now")
      end
    end

    def get(path, options = {})
      response = super
      raise APIError, "API request failed: #{response.code}" unless response.success?

      response.parsed_response
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

  class APIError < StandardError; end
end
