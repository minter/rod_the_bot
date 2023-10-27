module RodTheBot
  class SeasonStatsWorker
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper
    include ActiveSupport::Inflector

    def perform(your_team)
      skater_stats, goalie_stats = collect_roster_stats

      goalie_post = <<~POST
        🥅 Season goaltending stats for the #{your_team["team"]["name"]}

        #{goalie_stats.sort_by { |k, v| v[:wins] }.reverse.map { |player| "#{player[1][:name]}: #{player[1][:wins]}-#{player[1][:losses]}, #{player[1][:save_percentage]} save pct, #{player[1][:goals_against_average]} GAA" }.join("\n")}
      POST

      skater_points_leader_post = <<~POST
        📈 Season points leaders for the #{your_team["team"]["name"]}

        #{skater_stats.sort_by { |k, v| v[:points] }.last(4).reverse.map { |player| "#{player[1][:name]}: #{player[1][:points]} #{"point".pluralize(player[1][:points])}, (#{player[1][:goals]} #{"goal".pluralize(player[1][:goals])}, #{player[1][:assists]} #{"assist".pluralize(player[1][:assists])})" }.join("\n")}
      POST

      time_on_ice_leader_post = <<~POST
        ⏱️ Season time on ice leaders for the #{your_team["team"]["name"]}

        #{skater_stats.sort_by { |k, v| v[:time_on_ice] }.last(4).reverse.map { |player| "#{player[1][:name]}: #{player[1][:time_on_ice]}" }.join("\n")}
      POST

      goal_leader_post = <<~POST
        🚨 Season goal scoring leaders for the #{your_team["team"]["name"]}

        #{skater_stats.sort_by { |k, v| v[:goals] }.last(4).reverse.map { |player| "#{player[1][:name]}: #{player[1][:goals]} #{"goal".pluralize(player[1][:goals])}" }.join("\n")}
      POST

      assist_leader_post = <<~POST
        🏒 Season assist leaders for the #{your_team["team"]["name"]}

        #{skater_stats.sort_by { |k, v| v[:assists] }.last(4).reverse.map { |player| "#{player[1][:name]}: #{player[1][:assists]} #{"assist".pluralize(player[1][:assists])}" }.join("\n")}
      POST

      pim_leader_post = <<~POST
        🚔 Season penalty minute leaders for the #{your_team["team"]["name"]}

        #{skater_stats.sort_by { |k, v| v[:pim] }.last(4).reverse.map { |player| "#{player[1][:name]}: #{player[1][:pim]} #{"minute".pluralize(player[1][:pim])}" }.join("\n")}
      POST

      team_season_stats_post_1 = <<~POST
        📊 Season stats and NHL ranks for the #{your_team["team"]["name"]} (1/3)

        Average Goals Scored: #{season_stats_with_rank[:average_goals_scored][:value]} (Rank: #{season_stats_with_rank[:average_goals_scored][:rank]})
        Average Goals Allowed: #{season_stats_with_rank[:average_goals_allowed][:value]} (Rank: #{season_stats_with_rank[:average_goals_allowed][:rank]})
        Power Play Percentage: #{season_stats_with_rank[:power_play_percentage][:value]} (Rank: #{season_stats_with_rank[:power_play_percentage][:rank]})
      POST

      team_season_stats_post_2 = <<~POST
        📊 Season stats and NHL ranks for the #{your_team["team"]["name"]} (2/3)

        Penalty Kill Percentage: #{season_stats_with_rank[:penalty_kill_percentage][:value]} (Rank: #{season_stats_with_rank[:penalty_kill_percentage][:rank]})
        Shots Per Game: #{season_stats_with_rank[:shots_per_game][:value]} (Rank: #{season_stats_with_rank[:shots_per_game][:rank]})
        Shots Allowed Per Game: #{season_stats_with_rank[:shots_allowed_per_game][:value]} (Rank: #{season_stats_with_rank[:shots_allowed_per_game][:rank]})
      POST

      team_season_stats_post_3 = <<~POST
        📊 Season stats and NHL ranks for the #{your_team["team"]["name"]} (3/3)

        Faceoff Percentage: #{season_stats_with_rank[:faceoff_percentage][:value]} (Rank: #{season_stats_with_rank[:faceoff_percentage][:rank]})
        Shooting Percentage: #{season_stats_with_rank[:shooting_percentage][:value]} (Rank: #{season_stats_with_rank[:shooting_percentage][:rank]})
      POST

      RodTheBot::Post.perform_in(10, goalie_post)
      RodTheBot::Post.perform_in(20, time_on_ice_leader_post)
      RodTheBot::Post.perform_in(30, skater_points_leader_post)
      RodTheBot::Post.perform_in(40, goal_leader_post)
      RodTheBot::Post.perform_in(50, assist_leader_post)
      RodTheBot::Post.perform_in(60, pim_leader_post)
      RodTheBot::Post.perform_in(70, team_season_stats_post_1)
      RodTheBot::Post.perform_in(80, team_season_stats_post_2)
      RodTheBot::Post.perform_in(90, team_season_stats_post_3)
    end

    def collect_roster_stats
      skater_stats = {}
      goalie_stats = {}
      roster = HTTParty.get("https://statsapi.web.nhl.com/api/v1/teams/#{ENV["NHL_TEAM_ID"]}?expand=team.roster")["teams"].first["roster"]["roster"]
      roster.each do |player|
        player_id = player["person"]["id"]
        player_stats = HTTParty.get("https://statsapi.web.nhl.com/api/v1/people/#{player_id}/stats?stats=statsSingleSeason&season=20232024")
        next if player_stats["stats"].empty?
        next if player_stats["stats"].first["splits"].empty?
        stats = player_stats["stats"].first["splits"].first["stat"]
        next if stats["games"] == 0

        if player["position"]["code"] == "G"
          goalie_stats[player_id] = {
            name: player["person"]["fullName"],
            games: stats["games"],
            wins: stats["wins"],
            losses: stats["losses"],
            save_percentage: stats["savePercentage"].round(3),
            goals_against_average: stats["goalAgainstAverage"].round(3)
          }
        else
          skater_stats[player_id] = {
            name: player["person"]["fullName"],
            games: stats["games"],
            goals: stats["goals"],
            assists: stats["assists"],
            points: stats["points"],
            plus_minus: stats["plusMinus"],
            pim: stats["pim"],
            time_on_ice: stats["timeOnIcePerGame"]
          }
        end
      end
      [skater_stats, goalie_stats]
    end

    def season_stats_with_rank
      team_stats = HTTParty.get("https://statsapi.web.nhl.com/api/v1/teams/#{ENV["NHL_TEAM_ID"]}/stats?stats=statsSingleSeason&season=20232024")["stats"][0]["splits"][0]["stat"]
      team_ranks = HTTParty.get("https://statsapi.web.nhl.com/api/v1/teams/#{ENV["NHL_TEAM_ID"]}/stats?stats=statsSingleSeason&season=20232024")["stats"][1]["splits"][0]["stat"]
      faceoff_percentage = team_stats["faceOffWinPercentage"].to_f.round(1)
      average_goals_scored = team_stats["goalsPerGame"].to_f.round(1)
      average_goals_allowed = team_stats["goalsAgainstPerGame"].to_f.round(1)
      shots_per_game = team_stats["shotsPerGame"].to_f.round(1)
      shots_allowed_per_game = team_stats["shotsAllowed"].to_f.round(1)
      shooting_percentage = team_stats["shootingPctg"].to_f.round(2)
      power_play_percentage = team_stats["powerPlayPercentage"].to_f.round(2)
      penalty_kill_percentage = team_stats["penaltyKillPercentage"].to_f.round(2)
      faceoff_rank = team_ranks["faceOffWinPercentage"]
      goals_scored_rank = team_ranks["goalsPerGame"]
      goals_allowed_rank = team_ranks["goalsAgainstPerGame"]
      shots_per_game_rank = team_ranks["shotsPerGame"]
      shots_allowed_per_game_rank = team_ranks["shotsAllowed"]
      shooting_percentage_rank = team_ranks["shootingPctRank"]
      power_play_percentage_rank = team_ranks["powerPlayPercentage"]
      penalty_kill_percentage_rank = team_ranks["penaltyKillPercentage"]
      {
        faceoff_percentage: {value: faceoff_percentage, rank: faceoff_rank},
        average_goals_scored: {value: average_goals_scored, rank: goals_scored_rank},
        average_goals_allowed: {value: average_goals_allowed, rank: goals_allowed_rank},
        shots_per_game: {value: shots_per_game, rank: shots_per_game_rank},
        shots_allowed_per_game: {value: shots_allowed_per_game, rank: shots_allowed_per_game_rank},
        shooting_percentage: {value: shooting_percentage, rank: shooting_percentage_rank},
        power_play_percentage: {value: power_play_percentage, rank: power_play_percentage_rank},
        penalty_kill_percentage: {value: penalty_kill_percentage, rank: penalty_kill_percentage_rank}
      }
    end
  end
end
