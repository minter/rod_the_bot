module RodTheBot
  class EndOfPeriodStatsWorker
    include Sidekiq::Worker

    def perform(game_id, period_number)
      @feed = HTTParty.get("https://statsapi.web.nhl.com/api/v1/game/#{game_id}/feed/live")
      @home = @feed["liveData"]["linescore"]["teams"]["home"]
      @visitor = @feed["liveData"]["linescore"]["teams"]["away"]
      @your_team = (@home["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i) ? @home : @visitor
      @your_team_status = (@your_team["team"]["id"] == @home["team"]["id"]) ? "home" : "away"
      @home_code = @feed["gameData"]["teams"]["home"]["abbreviation"]
      @visitor_code = @feed["gameData"]["teams"]["away"]["abbreviation"]

      period_state = if @feed["gameData"]["status"]["detailedState"] == "Final"
        "at the end of the game"
      else
        "after the #{period_number} period"
      end

      period_toi_post = <<~POST
        ⏱️ Time on ice leaders for the #{@your_team["team"]["name"]} #{period_state}

        #{time_on_ice_leaders.map { |player| "#{player[1][:name]} - #{player[1][:toi]}" }.join("\n")}
      POST

      shots_on_goal_post = <<~POST
        🏒 Shots on goal leaders for the #{@your_team["team"]["name"]} #{period_state}

        #{shots_on_goal_leaders.map { |player| "#{player[1][:name]} - #{player[1][:shots]}" }.join("\n")}
      POST

      game_splits_stats = get_game_splits_stats
      game_split_stats_post = <<~POST
        📄 Game comparison #{period_state}

        Faceoff %: #{@visitor_code} - #{game_splits_stats[:faceOffWinPercentage][:away]}% | #{@home_code} - #{game_splits_stats[:faceOffWinPercentage][:home]}%
        PIM: #{@visitor_code} - #{game_splits_stats[:pim][:away]} | #{@home_code} - #{game_splits_stats[:pim][:home]}
        Blocks: #{@visitor_code} - #{game_splits_stats[:blocks][:away]} | #{@home_code} - #{game_splits_stats[:blocks][:home]}
        Takeaways: #{@visitor_code} - #{game_splits_stats[:takeaways][:away]} | #{@home_code} - #{game_splits_stats[:takeaways][:home]}
        Giveaways: #{@visitor_code} - #{game_splits_stats[:giveaways][:away]} | #{@home_code} - #{game_splits_stats[:giveaways][:home]}
        Hits: #{@visitor_code} - #{game_splits_stats[:hits][:away]} | #{@home_code} - #{game_splits_stats[:hits][:home]}
        Power Play %: #{@visitor_code} - #{game_splits_stats[:powerPlayPercentage][:away]}% | #{@home_code} - #{game_splits_stats[:powerPlayPercentage][:home]}%
      POST

      RodTheBot::Post.perform_in(60, period_toi_post)
      RodTheBot::Post.perform_in(120, shots_on_goal_post)
      RodTheBot::Post.perform_in(180, game_split_stats_post)
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

    def get_game_splits_stats
      game_splits = @feed["liveData"]["boxscore"]["teams"]
      {
        pim: {home: game_splits["home"]["teamStats"]["teamSkaterStats"]["pim"], away: game_splits["away"]["teamStats"]["teamSkaterStats"]["pim"]},
        faceOffWinPercentage: {home: game_splits["home"]["teamStats"]["teamSkaterStats"]["faceOffWinPercentage"], away: game_splits["away"]["teamStats"]["teamSkaterStats"]["faceOffWinPercentage"]},
        blocks: {home: game_splits["home"]["teamStats"]["teamSkaterStats"]["blocked"], away: game_splits["away"]["teamStats"]["teamSkaterStats"]["blocked"]},
        takeaways: {home: game_splits["home"]["teamStats"]["teamSkaterStats"]["takeaways"], away: game_splits["away"]["teamStats"]["teamSkaterStats"]["takeaways"]},
        giveaways: {home: game_splits["home"]["teamStats"]["teamSkaterStats"]["giveaways"], away: game_splits["away"]["teamStats"]["teamSkaterStats"]["giveaways"]},
        hits: {home: game_splits["home"]["teamStats"]["teamSkaterStats"]["hits"], away: game_splits["away"]["teamStats"]["teamSkaterStats"]["hits"]},
        powerPlayPercentage: {home: game_splits["home"]["teamStats"]["teamSkaterStats"]["powerPlayPercentage"], away: game_splits["away"]["teamStats"]["teamSkaterStats"]["powerPlayPercentage"]}
      }
    end
  end
end
