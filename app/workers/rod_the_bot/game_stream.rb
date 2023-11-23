module RodTheBot
  class GameStream
    include Sidekiq::Worker

    def perform(game_id)
      @game_id = game_id
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/play-by-play")
      @game_final = @feed["plays"].find { |play| play["typeDescKey"] == "game-end" }.present?

      @feed["plays"].each do |play|
        if play["typeDescKey"] == "goal"
          if REDIS.get("#{@game_id}:#{play["eventId"]}").nil?
            RodTheBot::GoalWorker.perform_in(60, @game_id, play["eventId"])
            REDIS.set("#{game_id}:#{play["eventId"]}", "true", ex: 172800)
          end
        elsif play["typeDescKey"] == "penalty"
          if REDIS.get("#{@game_id}:#{play["eventId"]}").nil?
            RodTheBot::PenaltyWorker.perform_in(60, @game_id, play["eventId"])
            REDIS.set("#{game_id}:#{play["eventId"]}", "true", ex: 172800)
          end
        elsif play["typeDescKey"] == "period-start" && play["period"] == 1
          if REDIS.get("#{@game_id}:#{play["eventId"]}").nil?
            RodTheBot::GameStartWorker.perform_async(@game_id)
            REDIS.set("#{game_id}:#{play["eventId"]}", "true", ex: 172800)
          end
        elsif play["typeDescKey"] == "period-start"
          if REDIS.get("#{@game_id}:#{play["eventId"]}").nil?
            RodTheBot::PeriodStartWorker.perform_async(@game_id, play["period"])
            REDIS.set("#{game_id}:#{play["eventId"]}", "true", ex: 172800)
          end
        elsif play["typeDescKey"] == "period-end"
          if REDIS.get("#{@game_id}:#{play["eventId"]}").nil?
            RodTheBot::EndOfPeriodWorker.perform_async(@game_id, play["period"])
            REDIS.set("#{game_id}:#{play["eventId"]}", "true", ex: 172800)
          end
        end
      end

      if @game_final
        RodTheBot::FinalScoreWorker.perform_in(60, @game_id)
        RodTheBot::ThreeStarsWorker.perform_in(90, @game_id)
      else
        RodTheBot::GameStream.perform_in(30, @game_id)
      end
    end
  end
end
