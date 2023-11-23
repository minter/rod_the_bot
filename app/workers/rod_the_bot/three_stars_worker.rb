module RodTheBot
  class ThreeStarsWorker
    include Sidekiq::Worker

    def perform(game_id)
      @feed = HTTParty.get("https://api-web.nhle.com/v1/gamecenter/#{game_id}/landing")

      RodTheBot::ThreeStarsWorker.perform_in(60, game_id) and return unless @feed["summary"]["threeStars"].present?

      post = <<~POST
        Three Stars Of The Game:

        ⭐️⭐️⭐️ #{player_stats(@feed["summary"]["threeStars"][2])}
        ⭐️⭐️ #{player_stats(@feed["summary"]["threeStars"][1])}
        ⭐️ #{player_stats(@feed["summary"]["threeStars"][0])}
      POST

      RodTheBot::Post.perform_async(post)
    end

    def player_stats(player)
      if player["position"] == "G"
        gaa = player["goalsAgainstAverage"]
        sv_pct = player["savePctg"].round(3)
        stats = if gaa.to_i == 0 && sv_pct.to_i == 1
          "Shutout"
        else
          "#{gaa} GAA, #{sv_pct} SV%"
        end
      else
        goals = player["goals"]
        assists = player["assists"]
        points = player["points"]
        stats = "#{goals}G #{assists}A, #{points}#{"PT".pluralize(points).upcase}"
      end
      "#{player["teamAbbrev"]} ##{player["sweaterNo"]} #{player["firstName"]} #{player["lastName"]} (#{stats})\n"
    end
  end
end
