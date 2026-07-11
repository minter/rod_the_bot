module RodTheBot
  class ActiveRosterFilter
    def self.call(data, players_key:, team_abbrev:)
      return data unless data && team_abbrev

      roster = NhlApi.roster(team_abbrev)
      active = data[players_key]&.select { |player| roster.key?(player.dig("player", "id")) } || []
      data.merge(players_key => active)
    end
  end
end
