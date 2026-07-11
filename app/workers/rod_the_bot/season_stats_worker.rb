module RodTheBot
  class SeasonStatsWorker
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper
    include ActiveSupport::Inflector

    def perform(your_team)
      @season = nil
      @season_type = nil
      @season_type_id = nil
      skater_stats, goalie_stats = collect_roster_stats
      return if Nhl::SeasonCalendar.preseason?
      return if skater_stats.empty? || goalie_stats.empty?

      presentation = SeasonStats::Formatter.new(season_type: @season_type, team_name: your_team)
      leaders = ->(stat) { top_skaters(skater_stats, stat) }

      goalie_post = presentation.goalie(goalie_stats)
      skater_points_leader_post = presentation.skaters(leaders.call(:points), :points, icon: "📈", title: "points leaders") { |p| "#{p[:name]}: #{p[:points]} #{"point".pluralize(p[:points])}, (#{p[:goals]} G, #{p[:assists]} A)" }
      time_on_ice_leader_post = presentation.skaters(leaders.call(:time_on_ice), :time_on_ice, icon: "⏱️", title: "time on ice leaders") { |p| "#{p[:name]}: #{Time.at(p[:time_on_ice]).strftime("%M:%S")}" }
      goal_leader_post = presentation.skaters(leaders.call(:goals), :goals, icon: "🚨", title: "goal scoring leaders") { |p| "#{p[:name]}: #{p[:goals]} #{"goal".pluralize(p[:goals])}" }
      assist_leader_post = presentation.skaters(leaders.call(:assists), :assists, icon: "🏒", title: "assist leaders") { |p| "#{p[:name]}: #{p[:assists]} #{"assist".pluralize(p[:assists])}" }
      pim_leader_post = presentation.skaters(leaders.call(:pim), :pim, icon: "🚔", title: "penalty minute leaders") { |p| "#{p[:name]}: #{p[:pim]} #{"min".pluralize(p[:pim])}" }
      rankings = season_stats_with_rank
      team_season_stats_post_1 = presentation.team_rankings(rankings, part: 1)
      team_season_stats_post_2 = presentation.team_rankings(rankings, part: 2)

      # Generate unique keys for each post that include the current date
      current_date = Time.now.strftime("%Y%m%d")
      stats_post_1_key = "season_stats:#{@season}:#{@season_type}:#{current_date}:1"
      stats_post_2_key = "season_stats:#{@season}:#{@season_type}:#{current_date}:2"

      # Schedule the posts with delays and keys
      RodTheBot::Post.perform_in(30.minutes, goalie_post)
      RodTheBot::Post.perform_in(45.minutes, time_on_ice_leader_post)
      RodTheBot::Post.perform_in(46.minutes, pim_leader_post)
      RodTheBot::Post.perform_in(60.minutes, skater_points_leader_post)
      RodTheBot::Post.perform_in(61.minutes, goal_leader_post)
      RodTheBot::Post.perform_in(62.minutes, assist_leader_post)

      RodTheBot::Post.perform_in(75.minutes, team_season_stats_post_1, stats_post_1_key)
      RodTheBot::Post.perform_in(76.minutes, team_season_stats_post_2, stats_post_2_key, stats_post_1_key)
    end

    def collect_roster_stats
      skater_stats = {}
      goalie_stats = {}
      roster = Nhl::PlayerClient.club_stats(ENV["NHL_TEAM_ABBREVIATION"])
      @season = roster["season"]
      @season_type_id = roster["gameType"]
      @season_type = case roster["gameType"]
      when 1
        "Preseason"
      when 2
        "Season"
      when 3
        "Playoff"
      end

      @season_type = "#{@season[0..3]}-#{@season[4..7]} #{@season_type}" if @season != Nhl::SeasonCalendar.current_season

      roster["skaters"].each do |player|
        skater_stats[player["playerId"]] = {
          name: Nhl::PlayerIdentity.from_landing(player, player_id: player["playerId"]).name_with_number,
          games: player["gamesPlayed"],
          goals: player["goals"],
          assists: player["assists"],
          points: player["points"],
          plus_minus: player["plusMinus"],
          pim: player["penaltyMinutes"],
          time_on_ice: player["avgTimeOnIcePerGame"]
        }
      end

      roster["goalies"].each do |player|
        goalie_stats[player["playerId"]] = {
          name: Nhl::PlayerIdentity.from_landing(player, player_id: player["playerId"]).name_with_number,
          games: player["gamesPlayed"],
          wins: player["wins"],
          losses: player["losses"],
          overtime_losses: player["overtimeLosses"],
          save_percentage: sprintf("%.3f", player["savePercentage"].round(3)),
          goals_against_average: sprintf("%.2f", player["goalsAgainstAverage"].round(2))
        }
      end
      [skater_stats, goalie_stats]
    end

    def top_skaters(skater_stats, stat_key, limit: 5)
      skater_stats.reject { |_, v| v[stat_key].to_f.zero? }
        .sort_by { |_, v| v[stat_key] }
        .last(limit)
        .reverse
    end

    def fetch_stats_and_rank(stat)
      data = Nhl::StatsClient.team_summary(season: @season, game_type: @season_type_id, sort: stat)
      # In stats against, the lower numbers are better. In other cases, the higher numbers are better
      data = data.reverse unless stat.include?("Against")
      data.each_with_index do |team, index|
        if team["teamId"] == ENV["NHL_TEAM_ID"].to_i
          value = case stat
          when /Pct$/
            (team[stat] * 100).round(1).to_s + "%"
          when /PerGame$/
            team[stat].round(2)
          else
            team[stat]
          end
          return {value: value, rank: ordinalize(index + 1)}
        end
      end
    end

    def season_stats_with_rank
      {
        faceoff_percentage: fetch_stats_and_rank("faceoffWinPct"),
        average_goals_scored: fetch_stats_and_rank("goalsForPerGame"),
        average_goals_allowed: fetch_stats_and_rank("goalsAgainstPerGame"),
        shots_per_game: fetch_stats_and_rank("shotsForPerGame"),
        shots_allowed_per_game: fetch_stats_and_rank("shotsAgainstPerGame"),
        points_percentage: fetch_stats_and_rank("pointPct"),
        power_play_percentage: fetch_stats_and_rank("powerPlayPct"),
        penalty_kill_percentage: fetch_stats_and_rank("penaltyKillPct")
      }
    end
  end
end
