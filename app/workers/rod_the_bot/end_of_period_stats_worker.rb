module RodTheBot
  class EndOfPeriodStatsWorker
    include Sidekiq::Worker

    def perform(game_id, period_number)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/boxscore")
      @home = @feed["homeTeam"]
      @visitor = @feed["awayTeam"]
      @your_team = (@home["id"].to_i == ENV["NHL_TEAM_ID"].to_i) ? @home : @visitor
      @your_team_status = (@your_team["id"] == @home["id"]) ? "homeTeam" : "awayTeam"
      @home_code = @home["abbrev"]
      @visitor_code = @visitor["abbrev"]

      period_state = if @feed["gameState"] == "OFF" || period_number.blank?
        "at the end of the game"
      else
        "after the #{period_number} period"
      end

      period_toi_post = <<~POST
        ⏱️ Time on ice leaders for the #{@your_team["name"]["default"]} #{period_state}

        #{time_on_ice_leaders.map { |player| "#{player[1][:name]} - #{player[1][:toi]}" }.join("\n")}
      POST

      shots_on_goal_post = <<~POST
        🏒 Shots on goal leaders for the #{@your_team["name"]["default"]} #{period_state}

        #{shots_on_goal_leaders.map { |player| "#{player[1][:name]} - #{player[1][:shots]}" }.join("\n")}
      POST

      game_splits_stats = get_game_splits_stats
      game_split_stats_post = <<~POST
        📄 Game comparison #{period_state}

        Faceoff %: #{@visitor_code} - #{game_splits_stats[:faceOffWinPercentage][:away]}% | #{@home_code} - #{game_splits_stats[:faceOffWinPercentage][:home]}%
        PIM: #{@visitor_code} - #{game_splits_stats[:pim][:away]} | #{@home_code} - #{game_splits_stats[:pim][:home]}
        Blocks: #{@visitor_code} - #{game_splits_stats[:blocks][:away]} | #{@home_code} - #{game_splits_stats[:blocks][:home]}
        Hits: #{@visitor_code} - #{game_splits_stats[:hits][:away]} | #{@home_code} - #{game_splits_stats[:hits][:home]}
        Power Play: #{@visitor_code} - #{game_splits_stats[:powerPlayConversion][:away]} | #{@home_code} - #{game_splits_stats[:powerPlayConversion][:home]}
      POST

      RodTheBot::Post.perform_in(60, period_toi_post)
      RodTheBot::Post.perform_in(120, shots_on_goal_post)
      RodTheBot::Post.perform_in(180, game_split_stats_post)
    end

    def time_on_ice_leaders
      team = @feed["boxscore"]["playerByGameStats"][@your_team_status]["forwards"] + @feed["boxscore"]["playerByGameStats"][@your_team_status]["defense"]
      @players = {}
      team.each do |player|
        @players[player["playerId"]] = {
          name: player["name"]["default"],
          toi: player["toi"]
        }
      end

      @players = @players.sort_by do |k, v|
        toi_minutes, toi_seconds = v[:toi].split(":").map(&:to_i)
        toi_minutes * 60 + toi_seconds
      end.last(5).reverse
    end

    def shots_on_goal_leaders
      team = @feed["boxscore"]["playerByGameStats"][@your_team_status]["forwards"] + @feed["boxscore"]["playerByGameStats"][@your_team_status]["defense"]
      @players = {}
      team.each do |player|
        @players[player["playerId"]] = {
          name: player["name"]["default"],
          shots: player["shots"]
        }
      end

      @players = @players.sort_by do |k, v|
        v[:shots]
      end.last(5).reverse
    end

    def get_game_splits_stats
      {
        pim: {home: @home["pim"], away: @visitor["pim"]},
        faceOffWinPercentage: {home: @home["faceoffWinningPctg"], away: @visitor["faceoffWinningPctg"]},
        blocks: {home: @home["blocks"], away: @visitor["blocks"]},
        hits: {home: @home["hits"], away: @visitor["hits"]},
        powerPlayConversion: {home: @home["powerPlayConversion"], away: @visitor["powerPlayConversion"]}
      }
    end
  end
end
