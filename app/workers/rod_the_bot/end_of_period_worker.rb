module RodTheBot
  class EndOfPeriodWorker
    include Sidekiq::Worker
    include WorkerErrorHandling
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter

    attr_reader :feed, :game_final

    def perform(game_id, play)
      @feed = Nhl::GameClient.play_by_play(game_id)
      @game_final = feed["plays"].any? { |play| play["typeDescKey"] == "game-end" }
      return if game_final
      return if play["periodDescriptor"]["periodType"] == "SO"

      home = feed.fetch("homeTeam", {})
      away = feed.fetch("awayTeam", {})
      period_descriptor = play.fetch("periodDescriptor", {})

      end_of_period_post = format_post(home, away, period_descriptor)
      record_line = situational_record_line(game_id, home, away, period_descriptor)
      end_of_period_post = "#{end_of_period_post}\n#{record_line}\n" if record_line

      RodTheBot::Post.perform_async(end_of_period_post)
      RodTheBot::EndOfPeriodStatsWorker.perform_in(60, game_id, period_descriptor.fetch("number", 1))
      RodTheBot::EndOfPeriodShotChartWorker.perform_in(75, game_id, period_descriptor.fetch("number", 1))
    rescue Nhl::RequestError => e
      retry_job(e, game_id: game_id, operation: "fetch_period_end")
    rescue => e
      retry_job(e, game_id: game_id, operation: "process_period_end")
    end

    private

    # The record line is an optional enhancement; the period summary posts without it.
    def situational_record_line(game_id, home, away, period_descriptor)
      team, opponent = (home["id"].to_i == ENV["NHL_TEAM_ID"].to_i) ? [home, away] : [away, home]
      RodTheBot::SituationalRecord
        .for_game(game_id, team_name: team.dig("commonName", "default"))
        .after_period(period_descriptor["number"], team_score: team.fetch("score", 0), opponent_score: opponent.fetch("score", 0))
    rescue Nhl::RequestError => e
      Rails.logger.warn "EndOfPeriodWorker: situational record unavailable for game #{game_id}: #{e.message}"
      nil
    end

    def format_post(home, away, period_descriptor)
      period_number = period_descriptor.fetch("number", 1)
      period_name = format_period_name(period_number)

      <<~POST
        🛑 That's the end of the #{period_name}!

        #{away.fetch("commonName", {}).fetch("default", "")} - #{away.fetch("score", 0)} 
        #{home.fetch("commonName", {}).fetch("default", "")} - #{home.fetch("score", 0)}

        Shots on goal after the #{period_name}:

        #{away.fetch("commonName", {}).fetch("default", "")}: #{away.fetch("sog", 0)}
        #{home.fetch("commonName", {}).fetch("default", "")}: #{home.fetch("sog", 0)}
      POST
    end
  end
end
