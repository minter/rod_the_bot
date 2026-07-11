module Nhl
  class PlayerIdentity
    attr_reader :id, :first_name, :last_name, :sweater_number, :team_id,
      :team_abbreviation, :position

    def initialize(id:, first_name:, last_name:, sweater_number: nil, team_id: nil,
      team_abbreviation: nil, position: nil)
      @id = id&.to_i
      @first_name = first_name
      @last_name = last_name
      @sweater_number = sweater_number
      @team_id = team_id&.to_i
      @team_abbreviation = team_abbreviation
      @position = position
    end

    def full_name
      [first_name, last_name].compact_blank.join(" ").presence || "Unknown Player"
    end

    def name_with_number
      "##{sweater_number.presence || "?"} #{full_name}"
    end

    def abbreviated_name
      return full_name unless first_name.present? && last_name.present?

      "#{first_name.first}. #{last_name}"
    end

    def self.from_game_roster(player, team_abbreviation: nil)
      new(
        id: player["playerId"],
        first_name: localized(player["firstName"]),
        last_name: localized(player["lastName"]),
        sweater_number: player["sweaterNumber"],
        team_id: player["teamId"],
        team_abbreviation: team_abbreviation,
        position: player["positionCode"]
      )
    end

    def self.from_team_roster(player, team_abbreviation:)
      new(
        id: player["id"],
        first_name: localized(player["firstName"]),
        last_name: localized(player["lastName"]),
        sweater_number: player["sweaterNumber"],
        team_id: player["teamId"],
        team_abbreviation: team_abbreviation,
        position: player["positionCode"] || player["position"]
      )
    end

    def self.from_landing(player, player_id: nil)
      new(
        id: player["playerId"] || player_id,
        first_name: localized(player["firstName"]),
        last_name: localized(player["lastName"]),
        sweater_number: player["sweaterNumber"],
        team_id: player["currentTeamId"],
        team_abbreviation: player["currentTeamAbbrev"],
        position: player["position"]
      )
    end

    def self.localized(value)
      value.is_a?(Hash) ? value["default"] || value.values.first : value
    end
    private_class_method :localized
  end
end
