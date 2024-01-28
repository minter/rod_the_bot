module RodTheBot
  class EndOfPeriodStatsWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector

    attr_reader :feed, :home, :visitor, :your_team, :your_team_status, :home_code, :visitor_code

    def perform(game_id, period_number)
      @game_id = game_id
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/landing")
      # return if @feed["gameState"] == "OFF"

      @home = feed.fetch("homeTeam", {})
      @visitor = feed.fetch("awayTeam", {})
      @your_team = (home.fetch("id", "").to_i == ENV["NHL_TEAM_ID"].to_i) ? home : visitor
      @your_team_status = (your_team.fetch("id", "") == home.fetch("id", "")) ? "homeTeam" : "awayTeam"
      @home_code = home.fetch("abbrev", "")
      @visitor_code = visitor.fetch("abbrev", "")
      @game_stats = @feed["summary"]["teamGameStats"]

      period_state = if feed.fetch("gameState", "") == "OFF" || period_number.blank?
        "at the end of the game"
      else
        "after the #{period_number} period"
      end

      period_toi_post = format_post(time_on_ice_leaders, "⏱️ Time on ice leaders", period_state)
      shots_on_goal_post = format_post(shots_on_goal_leaders, "🏒 Shots on goal leaders", period_state)

      game_splits_stats = get_game_splits_stats
      game_split_stats_post = format_game_split_stats_post(game_splits_stats, period_state)
      RodTheBot::Post.perform_in(180, game_split_stats_post)

      RodTheBot::Post.perform_in(60, period_toi_post)
      RodTheBot::Post.perform_in(120, shots_on_goal_post)
    end

    private

    def format_post(leaders, title, period_state)
      <<~POST
        #{title} for the #{your_team.fetch("name", {}).fetch("default", "")} #{period_state}

        #{leaders.map { |player| "#{player[1][:name]} - #{player[1][:stat]}" }.join("\n")}
      POST
    end

    def format_game_split_stats_post(game_splits_stats, period_state)
      <<~POST
        📄 Game comparison #{period_state}

        Faceoffs: #{visitor_code} - #{game_splits_stats[:faceoffPctg][:away]}% | #{home_code} - #{game_splits_stats[:faceoffPctg][:home]}%
        PIMs: #{visitor_code} - #{game_splits_stats[:pim][:away]} | #{home_code} - #{game_splits_stats[:pim][:home]}
        Blocks: #{visitor_code} - #{game_splits_stats[:blockedShots][:away]} | #{home_code} - #{game_splits_stats[:blockedShots][:home]}
        Hits: #{visitor_code} - #{game_splits_stats[:hits][:away]} | #{home_code} - #{game_splits_stats[:hits][:home]}
        Power Play: #{visitor_code} - #{game_splits_stats[:powerPlay][:away]} | #{home_code} - #{game_splits_stats[:powerPlay][:home]}
        Giveaways: #{visitor_code} - #{game_splits_stats[:giveaways][:away]} | #{home_code} - #{game_splits_stats[:giveaways][:home]}
        Takeaways: #{visitor_code} - #{game_splits_stats[:takeaways][:away]} | #{home_code} - #{game_splits_stats[:takeaways][:home]}
      POST
    end

    def create_players(stat)
      player_feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{@game_id}/boxscore")
      team = player_feed.fetch("boxscore", {}).fetch("playerByGameStats", {}).fetch(your_team_status, {}).fetch("forwards", []) +
        player_feed.fetch("boxscore", {}).fetch("playerByGameStats", {}).fetch(your_team_status, {}).fetch("defense", [])
      players = {}
      team.each do |player|
        players[player.fetch("playerId", "")] = {
          name: player.fetch("name", {}).fetch("default", ""),
          stat: player.fetch(stat, 0)
        }
      end
      players
    end

    def time_on_ice_leaders
      players = create_players("toi")
      players.sort_by do |k, v|
        toi_minutes, toi_seconds = v[:stat].split(":").map(&:to_i)
        [toi_minutes * 60 + toi_seconds, v[:name]]
      end.last(5).reverse
    end

    def shots_on_goal_leaders
      players = create_players("shots")
      players.sort_by { |k, v| [v[:stat], v[:name]] }.last(5).reverse
    end

    def get_game_splits_stats
      splits = {}
      @game_stats.each do |stat|
        splits[stat["category"].to_sym] = {home: stat["homeValue"], away: stat["awayValue"]}
      end
      splits
    end
  end
end
