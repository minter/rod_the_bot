module RodTheBot
  require "sidekiq-scheduler"

  class Scheduler
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper

    def perform
      @time_zone = TZInfo::Timezone.get(ENV["TIME_ZONE"])
      today = @time_zone.to_local(Time.now).strftime("%Y-%m-%d")
      @game = HTTParty.get("https://statsapi.web.nhl.com/api/v1/schedule?teamId=#{ENV["NHL_TEAM_ID"]}&date=#{today}")["dates"].first
      return if @game.nil?

      time = @time_zone.to_local(Time.parse(@game["games"].first["gameDate"])).strftime("%l:%M %p") + " " + @time_zone.abbreviation
      home = @game["games"].first["teams"]["home"]
      away = @game["games"].first["teams"]["away"]
      venue = @game["games"].first["venue"]

      game_id = @game["games"].first["gamePk"]

      your_team = if home["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        home
      else
        away
      end

      skater_stats, goalie_stats = collect_roster_stats

      if away["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i || home["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        gameday_post = <<~POST
          🗣️ It's a #{your_team["team"]["name"]} Gameday! 🗣️

          #{away["team"]["name"]}
          (#{record(away)}) 
          at 
          #{home["team"]["name"]}
          (#{record(home)})
          
          ⏰ #{time}
          📍 #{venue["name"]}
        POST

        goalie_post = <<~POST
          🥅 Season goaltending stats for the #{your_team["team"]["name"]} 🥅

          #{goalie_stats.sort_by { |k, v| v[:wins] }.reverse.map { |player| "#{player[1][:name]}: #{player[1][:wins]}-#{player[1][:losses]}, #{player[1][:save_percentage]} save pct, #{player[1][:goals_against_average]} GAA" }.join("\n")}
        POST

        skater_points_leader_post = <<~POST
          🏒 Season points leaders for the #{your_team["team"]["name"]} 🏒
          
          #{skater_stats.sort_by { |k, v| v[:points] }.last(5).reverse.map { |player| "#{player[1][:name]}: #{player[1][:points]} points, (#{pluralize player[1][:goals], "goal"}, #{pluralize player[1][:assists], "assist"})" }.join("\n")}
        POST

        time_on_ice_leader_post = <<~POST
          ⏱️ Season time on ice leaders for the #{your_team["team"]["name"]} ⏱️

          #{skater_stats.sort_by { |k, v| v[:time_on_ice] }.last(5).reverse.map { |player| "#{player[1][:name]}: #{player[1][:time_on_ice]}" }.join("\n")}
        POST

        RodTheBot::GameStream.perform_async(game_id)
        RodTheBot::Post.perform_async(gameday_post)
        RodTheBot::Post.perform_in(10, goalie_post)
        RodTheBot::Post.perform_in(20, skater_points_leader_post)
        RodTheBot::Post.perform_in(30, time_on_ice_leader_post)
      end
    end

    def record(team)
      points = team["leagueRecord"]["wins"] * 2 + team["leagueRecord"]["ot"]
      "#{team["leagueRecord"]["wins"]}-#{team["leagueRecord"]["losses"]}-#{team["leagueRecord"]["ot"]}, #{points} points"
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
  end
end
