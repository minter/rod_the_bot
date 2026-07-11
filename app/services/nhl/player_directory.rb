module Nhl
  class PlayerDirectory
    GAME_TTL = 6.hours
    TEAM_TTL = 6.hours

    def self.for_game(game_id)
      Rails.cache.fetch("nhl_game_player_directory_#{game_id}", expires_in: GAME_TTL) do
        from_game_feed(GameClient.play_by_play(game_id))
      end
    end

    def self.for_team(team_abbreviation)
      Rails.cache.fetch("nhl_team_player_directory_#{team_abbreviation}", expires_in: TEAM_TTL) do
        groups = get_team_roster(team_abbreviation)
        identities = %w[forwards defensemen goalies].flat_map { |group| groups.fetch(group, []) }.map do |player|
          PlayerIdentity.from_team_roster(player, team_abbreviation: team_abbreviation)
        end
        new(identities)
      end
    end

    def self.from_game_feed(feed)
      teams = [feed["homeTeam"], feed["awayTeam"]].compact.to_h do |team|
        [team["id"].to_i, team["abbrev"]]
      end
      identities = feed.fetch("rosterSpots", []).filter_map do |player|
        next unless player.is_a?(Hash) && player["playerId"].present?
        PlayerIdentity.from_game_roster(
          player,
          team_abbreviation: teams[player["teamId"].to_i]
        )
      end
      new(identities)
    end

    def self.get_team_roster(team_abbreviation)
      Roster.raw(team_abbreviation)
    end
    private_class_method :get_team_roster

    def initialize(identities)
      @identities = identities.index_by(&:id)
    end

    def fetch(player_id)
      @identities[player_id&.to_i]
    end

    def resolve(player_id)
      fetch(player_id) || begin
        identity = PlayerIdentity.from_landing(PlayerClient.landing(player_id), player_id: player_id)
        @identities[identity.id] = identity
      end
    end

    def full_name(player_id)
      fetch(player_id)&.full_name || "Unknown Player"
    end

    def name_with_number(player_id)
      fetch(player_id)&.name_with_number || "Unknown Player"
    end

    def sweater_number(player_id)
      fetch(player_id)&.sweater_number
    end

    def each(&block)
      @identities.each_value(&block)
    end

  end
end
