module RodTheBot
  class Scheduler
    include Sidekiq::Worker

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

      if away["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i || home["team"]["id"].to_i == ENV["NHL_TEAM_ID"].to_i
        post = <<~POST
          🗣️ It's a #{your_team["team"]["name"]} Gameday! 🗣️

          #{away["team"]["name"]}
          (#{record(away)}) 
          at 
          #{home["team"]["name"]}
          (#{record(home)})
          
          ⏰ #{time}
          📍 #{venue["name"]}
        POST
        RodTheBot::GameStream.perform_async(game_id)
        RodTheBot::Post.perform_async(post)
      end
    end

    def record(team)
      points = team["leagueRecord"]["wins"] * 2 + team["leagueRecord"]["ot"]
      "#{team["leagueRecord"]["wins"]}-#{team["leagueRecord"]["losses"]}-#{team["leagueRecord"]["ot"]}, #{points} points"
    end
  end
end
