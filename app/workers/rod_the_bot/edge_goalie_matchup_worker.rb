module RodTheBot
  class EdgeGoalieMatchupWorker
    include Sidekiq::Worker
    include PlayerImageHelper

    # Compare both starting goalies head-to-head
    # Called after game start when we know who's in net
    def perform(game_id, our_goalie_id, opponent_goalie_id)
      return if NhlApi.preseason?
      return unless our_goalie_id && opponent_goalie_id

      # Fetch EDGE data for both goalies
      our_data = NhlApi.fetch_goalie_detail(our_goalie_id)
      opp_data = NhlApi.fetch_goalie_detail(opponent_goalie_id)

      return unless our_data&.dig("player") && opp_data&.dig("player")

      # Format post
      post_text = format_goalie_matchup(our_data, opp_data)
      return unless post_text

      # Get both goalie headshots
      goalie_images = fetch_player_headshots([our_goalie_id, opponent_goalie_id])

      # Post as reply to game start thread
      current_date = Time.now.strftime("%Y%m%d")
      parent_key = "game_start_#{game_id}:#{current_date}"
      post_key = "edge_goalie_matchup_#{game_id}:#{current_date}"

      RodTheBot::Post.perform_async(post_text, post_key, parent_key, nil, goalie_images)
    rescue => e
      Rails.logger.error("EdgeGoalieMatchupWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_goalie_matchup(our_data, opp_data)
      our_player = our_data["player"]
      our_stats = our_data["stats"]
      opp_player = opp_data["player"]
      opp_stats = opp_data["stats"]

      return nil unless our_stats && opp_stats

      our_team = our_player.dig("team", "abbrev") || ENV["NHL_TEAM_ABBREVIATION"]
      opp_team = opp_player.dig("team", "abbrev") || "OPP"

      our_name = "#{our_player.dig("firstName", "default")} #{our_player.dig("lastName", "default")}"
      opp_name = "#{opp_player.dig("firstName", "default")} #{opp_player.dig("lastName", "default")}"

      # Extract key metrics
      our_gaa = our_stats.dig("goalsAgainstAvg", "value")
      our_gaa_pct = our_stats.dig("goalsAgainstAvg", "percentile")
      opp_gaa = opp_stats.dig("goalsAgainstAvg", "value")
      opp_gaa_pct = opp_stats.dig("goalsAgainstAvg", "percentile")

      our_goal_diff = our_stats.dig("goalDifferentialPer60", "value")
      our_goal_diff_pct = our_stats.dig("goalDifferentialPer60", "percentile")
      opp_goal_diff = opp_stats.dig("goalDifferentialPer60", "value")
      opp_goal_diff_pct = opp_stats.dig("goalDifferentialPer60", "percentile")

      our_point_pct = our_stats.dig("pointPctg", "value")
      our_point_pct_pct = our_stats.dig("pointPctg", "percentile")
      opp_point_pct = opp_stats.dig("pointPctg", "value")
      opp_point_pct_pct = opp_stats.dig("pointPctg", "percentile")

      # Count advantages
      advantages = count_advantages(our_stats, opp_stats)

      post = "🥅 GOALIE MATCHUP\n\n"

      # Our goalie
      post += "#{our_team}: #{our_name}\n"
      post += format_goalie_line(our_gaa, our_gaa_pct, our_goal_diff, our_goal_diff_pct, our_point_pct, our_point_pct_pct)
      post += "\n"

      # Opponent goalie
      post += "#{opp_team}: #{opp_name}\n"
      post += format_goalie_line(opp_gaa, opp_gaa_pct, opp_goal_diff, opp_goal_diff_pct, opp_point_pct, opp_point_pct_pct)

      # Verdict
      post += "\n"
      post += format_verdict(advantages, our_team, opp_team)

      post
    end

    def format_goalie_line(gaa, gaa_pct, goal_diff, goal_diff_pct, point_pct, point_pct_pct)
      lines = []

      if gaa && gaa_pct
        lines << "• #{sprintf("%.2f", gaa)} GAA (#{(gaa_pct * 100).round(0)}th %ile)"
      end

      if goal_diff && goal_diff_pct
        sign = (goal_diff >= 0) ? "+" : ""
        lines << "• #{sign}#{sprintf("%.2f", goal_diff)} goal diff/60 (#{(goal_diff_pct * 100).round(0)}th %ile)"
      end

      if point_pct && point_pct_pct
        lines << "• #{(point_pct * 100).round(1)}% point pct (#{(point_pct_pct * 100).round(0)}th %ile)"
      end

      lines.join("\n") + "\n"
    end

    def count_advantages(our_stats, opp_stats)
      metrics = %w[goalsAgainstAvg goalDifferentialPer60 pointPctg gamesAbove900]
      our_wins = 0
      opp_wins = 0

      metrics.each do |metric|
        our_pct = our_stats.dig(metric, "percentile")
        opp_pct = opp_stats.dig(metric, "percentile")

        next unless our_pct && opp_pct

        if our_pct > opp_pct
          our_wins += 1
        elsif opp_pct > our_pct
          opp_wins += 1
        end
      end

      {our: our_wins, opp: opp_wins}
    end

    def format_verdict(advantages, our_team, opp_team)
      if advantages[:our] > advantages[:opp]
        "Edge: #{our_team} 🔴"
      elsif advantages[:opp] > advantages[:our]
        "Edge: #{opp_team}"
      else
        "Edge: Even matchup ⚖️"
      end
    end
  end
end
