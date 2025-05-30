module RodTheBot
  class EndOfPeriodStatsWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter

    attr_reader :feed, :home, :visitor, :your_team, :your_team_status, :home_code, :visitor_code

    def perform(game_id, period_number)
      @game_id = game_id
      @feed = NhlApi.fetch_landing_feed(game_id)
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
        period_name = format_period_name(feed["periodDescriptor"]["number"].to_i)
        "after the #{period_name}"
      end

      period_toi_post = format_post(time_on_ice_leaders, "⏱️ Time on ice leaders", period_state)
      shots_on_goal_post = format_post(shots_on_goal_leaders, "🏒 Shots on goal leaders", period_state)

      game_splits_stats = NhlApi.splits(@game_id)
      game_split_stats_post = format_game_split_stats_post(game_splits_stats, period_state)

      # Generate unique keys for each period's set of posts
      current_date = Time.now.strftime("%Y%m%d")
      period_base_key = "end_period_stats:#{@game_id}:period#{period_number}:#{current_date}"
      toi_key = "#{period_base_key}:toi"
      sog_key = "#{period_base_key}:sog"
      splits_key = "#{period_base_key}:splits"

      # Post time on ice first
      RodTheBot::Post.perform_in(30.seconds, period_toi_post, toi_key)
      # Post shots on goal as reply to time on ice
      RodTheBot::Post.perform_in(31.seconds, shots_on_goal_post, sog_key, toi_key)
      # Post game splits as reply to shots on goal
      RodTheBot::Post.perform_in(32.seconds, game_split_stats_post, splits_key, sog_key)
    end

    private

    def format_post(leaders, title, period_state)
      <<~POST
        #{title} for the #{your_team.fetch("commonName", {}).fetch("default", "")} #{period_state}

        #{leaders.map { |player| "#{player[1][:name]} - #{player[1][:stat]}" }.join("\n")}
      POST
    end

    def format_game_split_stats_post(game_splits_stats, period_state)
      <<~POST
        📄 Game comparison #{period_state}

        Faceoffs: #{visitor_code} - #{game_splits_stats[:faceoffWinningPctg][:away]} | #{home_code} - #{game_splits_stats[:faceoffWinningPctg][:home]}
        PIMs: #{visitor_code} - #{game_splits_stats[:pim][:away]} | #{home_code} - #{game_splits_stats[:pim][:home]}
        Blocks: #{visitor_code} - #{game_splits_stats[:blockedShots][:away]} | #{home_code} - #{game_splits_stats[:blockedShots][:home]}
        Hits: #{visitor_code} - #{game_splits_stats[:hits][:away]} | #{home_code} - #{game_splits_stats[:hits][:home]}
        Power Play: #{visitor_code} - #{game_splits_stats[:powerPlay][:away]} | #{home_code} - #{game_splits_stats[:powerPlay][:home]}
        Giveaways: #{visitor_code} - #{game_splits_stats[:giveaways][:away]} | #{home_code} - #{game_splits_stats[:giveaways][:home]}
        Takeaways: #{visitor_code} - #{game_splits_stats[:takeaways][:away]} | #{home_code} - #{game_splits_stats[:takeaways][:home]}
      POST
    end

    def create_players(stat_category)
      player_feed = NhlApi.fetch_boxscore_feed(@game_id)
      team = player_feed.fetch("playerByGameStats", {}).fetch(@your_team_status, {}).fetch("forwards", []) +
        player_feed.fetch("playerByGameStats", {}).fetch(@your_team_status, {}).fetch("defense", [])
      players = {}
      team.each do |player|
        players[player.fetch("playerId", "")] = {
          name: player.fetch("name", {}).fetch("default", ""),
          stat: player.fetch(stat_category, 0)
        }
      end
      players
    end

    def time_on_ice_leaders
      players = create_players("toi")
      players.transform_values! do |player|
        minutes, seconds = player[:stat].split(":").map(&:to_i)
        player[:stat] = "#{minutes}:#{seconds.to_s.rjust(2, "0")}"
        player
      end
      players.sort_by do |k, v|
        toi_minutes, toi_seconds = v[:stat].split(":").map(&:to_i)
        [toi_minutes * 60 + toi_seconds, v[:name]]
      end.last(5).reverse
    end

    def shots_on_goal_leaders
      players = create_players("sog")
      players.sort_by { |k, v| [v[:stat], v[:name]] }.last(5).reverse
    end
  end
end
