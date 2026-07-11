module RodTheBot
  module Scheduling
    class EdgePosts
      WORKERS = [
        EdgePlayerZoneTimeWorker, EdgeTeamSpeedWorker, EdgeTeamShotSpeedWorker,
        EdgeMatchupWorker, EdgePlayerHotZonesWorker, EdgeSpecialTeamsWorker,
        EdgeEsMatchupWorker, EdgeSpeedDemonLeaderboardWorker, EdgePlayerWorkloadWorker
      ].freeze

      def schedule(game_id:, game_time:, now: Time.now)
        start = 15.minutes
        available = game_time - now - 30.minutes - start
        if available.negative?
          Rails.logger.warn "Scheduler: Game too soon, skipping EDGE posts"
          return
        end

        interval = available / (WORKERS.length + 1)
        WORKERS.each_with_index do |worker, index|
          delay = start + interval * (index + 1)
          worker.perform_in(delay, game_id)
          Rails.logger.info "Scheduler: #{worker.name} scheduled for #{delay.to_i / 60} minutes from now"
        end
      end
    end
  end
end
