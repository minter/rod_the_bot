module RodTheBot
  class EndOfPeriodWorker
    include Sidekiq::Worker

    def perform(game_id, period_number)
      @feed = HTTParty.get("https://statsapi.web.nhl.com/api/v1/game/#{game_id}/feed/live")
      @home = @feed["liveData"]["linescore"]["teams"]["home"]
      @visitor = @feed["liveData"]["linescore"]["teams"]["away"]
      @your_team = (@home["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i) ? @home : @visitor
      @your_team_status = (@your_team["team"]["id"] == @home["team"]["id"]) ? "home" : "away"

      end_of_period_post = <<~POST
        🗣️ That's the end of the #{period_number} period 🗣️

        #{@visitor["team"]["name"]} - #{@visitor["goals"]} 
        #{@home["team"]["name"]} - #{@home["goals"]}

        Shots on goal after the #{period_number} period:

        #{@visitor["team"]["name"]}: #{@visitor["shotsOnGoal"]}
        #{@home["team"]["name"]}: #{@home["shotsOnGoal"]}
      POST

      period_toi_post = <<~POST
        ⏱️ Time on ice leaders for the #{@your_team["team"]["name"]} after the #{period_number} period ⏱️

        #{time_on_ice_leaders.map { |player| "#{player[1][:name]} - #{player[1][:toi]}" }.join("\n")}
      POST

      shots_on_goal_post = <<~POST
        🏒 Shots on goal leaders for the #{@your_team["team"]["name"]} after the #{period_number} period 🏒

        #{shots_on_goal_leaders.map { |player| "#{player[1][:name]} - #{player[1][:shots]}" }.join("\n")}
      POST

      RodTheBot::Post.perform_async(end_of_period_post) unless @feed["gameData"]["status"]["detailedState"] == "Final"
      RodTheBot::Post.perform_in(10, period_toi_post)
      RodTheBot::Post.perform_in(20, shots_on_goal_post)
    end

    def time_on_ice_leaders
      team = @feed["liveData"]["boxscore"]["teams"][@your_team_status]
      @players = {}
      team["players"].each do |id, player|
        if player["position"]["code"] != "G" && player["stats"].present?
          @players[player["person"]["id"]] = {
            name: player["person"]["fullName"],
            toi: player["stats"]["skaterStats"]["timeOnIce"]
          }
        end
      end

      @players = @players.sort_by do |k, v|
        toi_minutes, toi_seconds = v[:toi].split(":").map(&:to_i)
        toi_minutes * 60 + toi_seconds
      end.last(5).reverse
    end

    def shots_on_goal_leaders
      team = @feed["liveData"]["boxscore"]["teams"][@your_team_status]
      @players = {}
      team["players"].each do |id, player|
        if player["position"]["code"] != "G" && player["stats"].present?
          @players[player["person"]["id"]] = {
            name: player["person"]["fullName"],
            shots: player["stats"]["skaterStats"]["shots"]
          }
        end
      end

      @players = @players.sort_by do |k, v|
        v[:shots]
      end.last(5).reverse
    end
  end
end
