module RodTheBot
  class GameMatchup
    Matchup = Data.define(:our_team_id, :our_abbrev, :opponent_team_id, :opponent_abbrev)

    def self.for(game_id, team_id: ENV.fetch("NHL_TEAM_ID").to_i)
      return unless game_id

      feed = NhlApi.fetch_landing_feed(game_id)
      return unless feed

      home = feed["homeTeam"]
      away = feed["awayTeam"]
      ours, opponent = home["id"].to_i == team_id ? [home, away] : [away, home]

      Matchup.new(
        our_team_id: ours["id"].to_i,
        our_abbrev: ours["abbrev"],
        opponent_team_id: opponent["id"].to_i,
        opponent_abbrev: opponent["abbrev"]
      )
    end
  end
end
