module RodTheBot
  # Builds the "The Hurricanes are 9-0-1 when leading after two periods this season." line
  # from the normalized records returned by Nhl::StatsClient.team_situational_records.
  class SituationalRecord
    PLAYOFFS = 3
    PERIODS = {1 => "one period", 2 => "two periods"}.freeze
    GAME_TYPES_WITH_RECORDS = [2, PLAYOFFS].freeze

    def self.for_game(game_id, team_name:, team_id: ENV["NHL_TEAM_ID"].to_i, fetch: Nhl::StatsClient.method(:team_situational_records))
      game = Nhl::GameId.new(game_id)
      records = if GAME_TYPES_WITH_RECORDS.include?(game.game_type)
        fetch.call(team_id: team_id, season: game.season, game_type: game.game_type)
      end
      new(records: records, team_name: team_name, game_type: game.game_type)
    end

    def initialize(records:, team_name:, game_type:)
      @records = records || {}
      @team_name = team_name
      @game_type = game_type.to_i
    end

    def after_period(period_number, team_score:, opponent_score:)
      period = PERIODS[period_number.to_i]
      return unless period

      state = if team_score > opponent_score
        "leading"
      elsif team_score < opponent_score
        "trailing"
      else
        "tied"
      end
      line(:"#{state}_after_#{period_number.to_i}", "when #{state} after #{period}")
    end

    def first_goal(scored_by_team:)
      if scored_by_team
        line(:scoring_first, "when scoring first")
      else
        line(:trailing_first, "when allowing the first goal")
      end
    end

    private

    attr_reader :records, :team_name, :game_type

    def line(situation, description)
      record = records[situation]
      return if record.nil? || record.values.sum.zero?

      "The #{team_name} are #{format_record(record)} #{description} #{timeframe}."
    end

    def format_record(record)
      parts = [record[:wins], record[:losses]]
      parts << record[:ot_losses] unless playoffs?
      parts.join("-")
    end

    def timeframe
      playoffs? ? "this postseason" : "this season"
    end

    def playoffs?
      game_type == PLAYOFFS
    end
  end
end
