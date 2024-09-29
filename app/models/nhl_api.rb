class NhlApi
  include HTTParty
  base_uri "https://api-web.nhle.com/v1"

  class << self
    def fetch_pbp_feed(game_id)
      get("/gamecenter/#{game_id}/play-by-play")
    end

    def fetch_boxscore_feed(game_id)
      get("/gamecenter/#{game_id}/boxscore")
    end

    def fetch_game_landing_feed(game_id)
      get("/gamecenter/#{game_id}/landing")
    end

    def fetch_player_landing_feed(player_id)
      get("/player/#{player_id}/landing")
    end

    def fetch_right_rail_feed(game_id)
      get("/gamecenter/#{game_id}/right-rail")
    end

    def fetch_schedule(date: Time.now.strftime("%Y-%m-%d"))
      Time.zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      get("/club-schedule/#{ENV["NHL_TEAM_ABBREVIATION"]}/week/#{date}")
    end

    def todays_game(date: Time.now.strftime("%Y-%m-%d"))
      fetch_schedule(date: date)["games"].find { |game| game["gameDate"] == date }
    end

    def fetch_team_standings(team_abbreviation)
      response = get("/standings/now")
      team = response["standings"].find { |t| t["teamAbbrev"]["default"] == team_abbreviation }

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

    def current_season
      get("/season").last
    end

    def postseason?
      season = current_season
      begin
        get("/playoff-series/carousel/#{season}/")["rounds"].present?
      rescue NhlApi::APIError
        false
      end
    end

    def preseason?(target_season)
      target_season != current_season
    end

    private

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
  end

  class APIError < StandardError; end
end
