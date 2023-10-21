module RodTheBot
  class ThreeStarsWorker
    include Sidekiq::Worker

    def perform(game_id)
      # https://statsapi.web.nhl.com/api/v1/game/2023020034/feed/live
      @feed = HTTParty.get("https://statsapi.web.nhl.com/api/v1/game/#{game_id}/feed/live")

      RodTheBot::ThreeStarsWorker.perform_in(60, game_id) and return unless @feed["liveData"]["decisions"]["firstStar"].present?

      @players = {}
      %w[home away].each do |team_type|
        @feed["liveData"]["boxscore"]["teams"][team_type]["players"].each do |id, player|
          @players[id] = player
          @players[id]["team"] = @feed["gameData"]["players"][id]["currentTeam"]["triCode"]
        end
      end

      first_star_id = "ID" + @feed["liveData"]["decisions"]["firstStar"]["id"].to_s
      second_star_id = "ID" + @feed["liveData"]["decisions"]["secondStar"]["id"].to_s
      third_star_id = "ID" + @feed["liveData"]["decisions"]["thirdStar"]["id"].to_s

      post = <<~POST
        Three Stars Of The Game:

        ⭐️⭐️⭐️ #{player_stats(@players, third_star_id)}
        ⭐️⭐️ #{player_stats(@players, second_star_id)}
        ⭐️ #{player_stats(@players, first_star_id)}
      POST

      RodTheBot::Post.perform_async(post)
    end

    def player_stats(players, id)
      player = players[id]
      player_info = ""
      if player["position"]["abbreviation"] == "G"
        decision = player["stats"]["goalieStats"]["decision"]
        shots = player["stats"]["goalieStats"]["shots"]
        saves = player["stats"]["goalieStats"]["saves"]
        player_info = "#{player["team"]} ##{player["jerseyNumber"]} #{player["person"]["fullName"]} (#{decision}, #{saves} saves on #{shots} shots)\n"
      else
        goals = player["stats"]["skaterStats"]["goals"]
        assists = player["stats"]["skaterStats"]["assists"]
        points = goals + assists
        stats = "#{goals}G #{assists}A, #{points}PTS"
        player_info = "#{player["team"]} ##{player["jerseyNumber"]} #{player["person"]["fullName"]} (#{stats})\n"
      end
      player_info
    end
  end
end
