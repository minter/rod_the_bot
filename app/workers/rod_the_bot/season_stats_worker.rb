module RodTheBot
  class SeasonStatsWorker
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper
    include ActiveSupport::Inflector

    def perform(your_team)
      @season = nil
      skater_stats, goalie_stats = collect_roster_stats

      goalie_post = <<~POST
        🥅 Season goaltending stats for the #{your_team}

        #{goalie_stats.sort_by { |k, v| v[:wins] }.reverse.map { |player| "#{player[1][:name]}: #{player[1][:wins]}-#{player[1][:losses]}, #{player[1][:save_percentage]} save pct, #{player[1][:goals_against_average]} GAA" }.join("\n")}
      POST

      skater_points_leader_post = <<~POST
        📈 Season points leaders for the #{your_team}

        #{skater_stats.sort_by { |k, v| v[:points] }.last(4).reverse.map { |player| "#{player[1][:name]}: #{player[1][:points]} #{"point".pluralize(player[1][:points])}, (#{player[1][:goals]} #{"goal".pluralize(player[1][:goals])}, #{player[1][:assists]} #{"assist".pluralize(player[1][:assists])})" }.join("\n")}
      POST

      time_on_ice_leader_post = <<~POST
        ⏱️ Season time on ice leaders for the #{your_team}

        #{skater_stats.sort_by { |k, v| v[:time_on_ice] }.last(4).reverse.map { |player| "#{player[1][:name]}: #{Time.at(player[1][:time_on_ice]).strftime("%M:%S")}" }.join("\n")}
      POST

      goal_leader_post = <<~POST
        🚨 Season goal scoring leaders for the #{your_team}

        #{skater_stats.sort_by { |k, v| v[:goals] }.last(4).reverse.map { |player| "#{player[1][:name]}: #{player[1][:goals]} #{"goal".pluralize(player[1][:goals])}" }.join("\n")}
      POST

      assist_leader_post = <<~POST
        🏒 Season assist leaders for the #{your_team}

        #{skater_stats.sort_by { |k, v| v[:assists] }.last(4).reverse.map { |player| "#{player[1][:name]}: #{player[1][:assists]} #{"assist".pluralize(player[1][:assists])}" }.join("\n")}
      POST

      pim_leader_post = <<~POST
        🚔 Season penalty minute leaders for the #{your_team}

        #{skater_stats.sort_by { |k, v| v[:pim] }.last(4).reverse.map { |player| "#{player[1][:name]}: #{player[1][:pim]} #{"minute".pluralize(player[1][:pim])}" }.join("\n")}
      POST

      team_season_stats_post_1 = <<~POST
        📊 Season stats and NHL ranks for the #{your_team} (1/3)

        Average Goals Scored: #{season_stats_with_rank[:average_goals_scored][:value]} (Rank: #{season_stats_with_rank[:average_goals_scored][:rank]})
        Average Goals Allowed: #{season_stats_with_rank[:average_goals_allowed][:value]} (Rank: #{season_stats_with_rank[:average_goals_allowed][:rank]})
        Power Play Percentage: #{season_stats_with_rank[:power_play_percentage][:value]} (Rank: #{season_stats_with_rank[:power_play_percentage][:rank]})
      POST

      team_season_stats_post_2 = <<~POST
        📊 Season stats and NHL ranks for the #{your_team} (2/3)

        Penalty Kill Percentage: #{season_stats_with_rank[:penalty_kill_percentage][:value]} (Rank: #{season_stats_with_rank[:penalty_kill_percentage][:rank]})
        Shots Per Game: #{season_stats_with_rank[:shots_per_game][:value]} (Rank: #{season_stats_with_rank[:shots_per_game][:rank]})
        Shots Allowed Per Game: #{season_stats_with_rank[:shots_allowed_per_game][:value]} (Rank: #{season_stats_with_rank[:shots_allowed_per_game][:rank]})
      POST

      team_season_stats_post_3 = <<~POST
        📊 Season stats and NHL ranks for the #{your_team} (3/3)

        Faceoff Percentage: #{season_stats_with_rank[:faceoff_percentage][:value]} (Rank: #{season_stats_with_rank[:faceoff_percentage][:rank]})
        Points Percentage: #{season_stats_with_rank[:points_percentage][:value]} (Rank: #{season_stats_with_rank[:points_percentage][:rank]})
      POST

      RodTheBot::Post.perform_in(30.minutes, goalie_post)
      RodTheBot::Post.perform_in(45.minutes, time_on_ice_leader_post)
      RodTheBot::Post.perform_in(46.minutes, pim_leader_post)
      RodTheBot::Post.perform_in(60.minutes, skater_points_leader_post)
      RodTheBot::Post.perform_in(61.minutes, goal_leader_post)
      RodTheBot::Post.perform_in(62.minutes, assist_leader_post)
      RodTheBot::Post.perform_in(75.minutes, team_season_stats_post_1)
      RodTheBot::Post.perform_in(76.minutes, team_season_stats_post_2)
      RodTheBot::Post.perform_in(77.minutes, team_season_stats_post_3)
    end

    def collect_roster_stats
      skater_stats = {}
      goalie_stats = {}
      roster = HTTParty.get("https://api-web.nhle.com/v1/club-stats/#{ENV["NHL_TEAM_ABBREVIATION"]}/now")
      @season = roster["season"]
      roster["skaters"].each do |player|
        skater_stats[player["playerId"]] = {
          name: player["firstName"]["default"] + " " + player["lastName"]["default"],
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
          name: player["firstName"]["default"] + " " + player["lastName"]["default"],
          games: player["gamesPlayed"],
          wins: player["wins"],
          losses: player["losses"],
          save_percentage: player["savePercentage"].round(3),
          goals_against_average: player["goalsAgainstAverage"].round(3)
        }
      end
      [skater_stats, goalie_stats]
    end

    def fetch_stats_and_rank(stat)
      feed = HTTParty.get("https://api.nhle.com/stats/rest/en/team/summary?sort=#{stat}&cayenneExp=seasonId=#{@season}%20and%20gameTypeId=2")
      # In stats against, the lower numbers are better. In other cases, the higher numbers are better
      data = stat.match?(/Against/) ? feed["data"] : feed["data"].reverse
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
