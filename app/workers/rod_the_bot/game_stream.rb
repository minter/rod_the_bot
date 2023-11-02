module RodTheBot
  class GameStream
    include Sidekiq::Worker

    def perform(game_id)
      @game_id = game_id
      @feed = HTTParty.get("https://statsapi.web.nhl.com/api/v1/game/#{game_id}/feed/live")
      @game_final = @feed["gameData"]["status"]["detailedState"] == "Final"
      @players = {}

      @feed["liveData"]["plays"]["allPlays"].each do |play|
        if play["result"]["event"] == "Goal"
          if REDIS.get("#{@game_id}:#{play["about"]["eventId"]}").nil?
            RodTheBot::GoalWorker.perform_in(60, @game_id, play["about"]["eventId"])
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
        elsif play["result"]["eventTypeId"] == "PERIOD_READY"
          if REDIS.get("#{@game_id}:#{play["about"]["eventId"]}").nil?
            RodTheBot::PeriodStartWorker.perform_async(@game_id, play["about"]["ordinalNum"])
            REDIS.set("#{game_id}:#{play["about"]["eventId"]}", "true", ex: 172800)
          end
        elsif play["result"]["eventTypeId"] == "PERIOD_END"
          if REDIS.get("#{@game_id}:#{play["about"]["eventId"]}").nil?
            RodTheBot::EndOfPeriodWorker.perform_async(@game_id, play["about"]["ordinalNum"]) unless play["about"]["periodType"] == "SHOOTOUT"
            REDIS.set("#{game_id}:#{play["about"]["eventId"]}", "true", ex: 172800)
          end
        end
      end

      if @game_final
        RodTheBot::FinalScoreWorker.perform_async(@game_id)
        RodTheBot::ThreeStarsWorker.perform_in(90, @game_id)
      else
        RodTheBot::GameStream.perform_in(30, @game_id)
      end
    end
  end
end
