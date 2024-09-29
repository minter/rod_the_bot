module RodTheBot
  class ThreeStarsWorker
    include Sidekiq::Worker

    attr_reader :feed

    def perform(game_id)
      @feed = NhlApi.fetch_landing_feed(game_id)

      if feed["summary"].present? && feed["summary"]["threeStars"].present?
        post = format_three_stars(feed["summary"]["threeStars"])
        post_three_stars(post)
      else
        RodTheBot::ThreeStarsWorker.perform_in(60, game_id)
      end
    end

    private

    def format_three_stars(three_stars)
      <<~POST
        Three Stars Of The Game:

        ⭐️⭐️⭐️ #{player_stats(three_stars[2])}
        ⭐️⭐️ #{player_stats(three_stars[1])}
        ⭐️ #{player_stats(three_stars[0])}
      POST
    end

    def player_stats(player)
      if player["position"] == "G"
        format_goalie_stats(player)
      else
        format_player_stats(player)
      end
    end

    def format_goalie_stats(player)
      gaa = player["goalsAgainstAverage"]
      sv_pct = sprintf("%.3f", player["savePctg"].round(3))
      stats = if gaa.to_i == 0 && sv_pct.to_i == 1
        "(Shutout)"
      else
        "(#{gaa} GAA, #{sv_pct} SV%)"
      end
      format_player_info(player, stats)
    end

    def format_player_stats(player)
      stat_collection = []
      stat_collection << "#{player["goals"]}G" if player["goals"].to_i > 0
      stat_collection << "#{player["assists"]}A" if player["assists"].to_i > 0
      stat_collection << "#{player["points"]}#{"PT".pluralize(player["points"]).upcase}" if player["points"].to_i > 0
      stats = stat_collection.join(", ")
      stats_output = stats.present? ? "(#{stats})" : ""
      format_player_info(player, stats_output)
    end

    def format_player_info(player, stats)
      "#{player["teamAbbrev"]} ##{player["sweaterNo"]} #{player["name"]["default"]} #{stats}\n"
    end

    def post_three_stars(post)
      RodTheBot::Post.perform_async(post)
    end
  end
end
