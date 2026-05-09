module RodTheBot
  class EndOfPeriodShotChartWorker
    include Sidekiq::Worker

    sidekiq_options retry: false

    PERIOD_NAMES = {1 => "1st", 2 => "2nd", 3 => "3rd", 4 => "OT"}.freeze

    def perform(game_id, period_number)
      feed = NhlApi.fetch_pbp_feed(game_id)
      home = feed["homeTeam"] || {}
      away = feed["awayTeam"] || {}

      path = RodTheBot::ShotChartAnimator.new(
        game_id: game_id,
        through_period: period_number
      ).call
      return if path.nil?

      post_text = format_post(home, away, period_number)
      RodTheBot::Post.perform_async(
        post_text,
        nil,
        nil,
        nil,
        [],
        path.to_s,
        nil
      )
    rescue NhlApi::APIError => e
      Rails.logger.error "EndOfPeriodShotChartWorker: API error for game #{game_id}: #{e.message}"
    rescue => e
      Rails.logger.error "EndOfPeriodShotChartWorker: Unexpected error for game #{game_id}: #{e.class} - #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    end

    private

    def format_post(home, away, period_number)
      label = PERIOD_NAMES[period_number] || "P#{period_number}"
      <<~POST
        🏒 Shot chart through the #{label} period.

        #{away.fetch("abbrev", "AWY")}: #{away.fetch("sog", 0)} SOG
        #{home.fetch("abbrev", "HME")}: #{home.fetch("sog", 0)} SOG
      POST
    end
  end
end
