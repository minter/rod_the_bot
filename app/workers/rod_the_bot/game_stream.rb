module RodTheBot
  class GameStream
    include Sidekiq::Worker

    def perform(game_id)
      @game_id = game_id
      @feed = HTTParty.get("https://statsapi.web.nhl.com/api/v1/game/#{game_id}/feed/live")
      @game_final = @feed["gameData"]["status"]["detailedState"] == "Final"
      @players = {}

      play_count = 0
      @feed["liveData"]["plays"]["allPlays"].each do |play|
        play_count += 1
        if play["result"]["event"] == "Goal"
          if REDIS.get("#{@game_id}:#{play["about"]["eventId"]}").nil?
            RodTheBot::GoalWorker.perform_in(120, @game_id, play["about"]["eventId"])
            REDIS.set("#{game_id}:#{play["about"]["eventId"]}", "true", ex: 172800)
          end
        elsif play["result"]["event"] == "Penalty"
          if REDIS.get("#{@game_id}:#{play["about"]["eventId"]}").nil?
            RodTheBot::PenaltyWorker.perform_in(60, @game_id, play["about"]["eventId"])
            REDIS.set("#{game_id}:#{play["about"]["eventId"]}", "true", ex: 172800)
          end
        elsif play["result"]["eventTypeId"] == "PERIOD_READY" && play["about"]["period"] == 1
          if REDIS.get("#{@game_id}:#{play["about"]["eventId"]}").nil?
            RodTheBot::GameStartWorker.perform_async(@game_id)
            REDIS.set("#{game_id}:#{play["about"]["eventId"]}", "true", ex: 172800)
          end
        elsif play["result"]["event"] == "Period Start" || play["result"]["event"] == "Period End"
          # TODO: Implement period start worker
        end
      end

      if @game_final
        RodTheBot::FinalScoreWorker.perform_in(60, @game_id)
        RodTheBot::ThreeStarsWorker.perform_in(90, @game_id)
      else
        RodTheBot::GameStream.perform_in(60, @game_id)
      end
    end
  end
end
