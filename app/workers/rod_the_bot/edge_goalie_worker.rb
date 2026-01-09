module RodTheBot
  class EdgeGoalieWorker
    include Sidekiq::Worker
    include PlayerImageHelper

    # Post EDGE stats for the starting goalie of our team
    # Called after game start when we know who's in net
    def perform(game_id, goalie_player_id)
      return if NhlApi.preseason?
      return unless goalie_player_id

      # Fetch EDGE goalie data
      goalie_data = NhlApi.fetch_goalie_detail(goalie_player_id)
      return unless goalie_data && goalie_data["player"]

      # Format post
      post_text = format_goalie_spotlight(goalie_data)
      return unless post_text

      # Get goalie headshot
      goalie_headshot = fetch_player_headshot(goalie_player_id)

      # Post as reply to game start thread
      current_date = Time.now.strftime("%Y%m%d")
      parent_key = "game_start_#{game_id}:#{current_date}"
      post_key = "edge_goalie_#{game_id}:#{current_date}"

      RodTheBot::Post.perform_async(post_text, post_key, parent_key, nil, [goalie_headshot])
    rescue => e
      Rails.logger.error("EdgeGoalieWorker error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end

    private

    def format_goalie_spotlight(goalie_data)
      player = goalie_data["player"]
      stats = goalie_data["stats"]
      shot_details = goalie_data["shotLocationDetails"]

      return nil unless player && stats

      goalie_name = "#{player["firstName"]["default"]} #{player["lastName"]["default"]}"
      sweater_number = player["sweaterNumber"]

      # Get overall stats with percentiles
      gaa = stats.dig("goalsAgainstAvg", "value")
      gaa_percentile = stats.dig("goalsAgainstAvg", "percentile")
      goal_diff = stats.dig("goalDifferentialPer60", "value")
      goal_diff_percentile = stats.dig("goalDifferentialPer60", "percentile")
      games_above_900 = stats.dig("gamesAbove900", "value")
      games_above_900_percentile = stats.dig("gamesAbove900", "percentile")
      point_pct = stats.dig("pointPctg", "value")
      point_pct_percentile = stats.dig("pointPctg", "percentile")

      # Find top save zones (best percentiles, with meaningful sample size)
      top_zones = []
      if shot_details&.any?
        top_zones = shot_details.select do |zone|
          zone["savePctgPercentile"] && zone["saves"] && zone["saves"] > 5
        end.sort_by { |z| -(z["savePctgPercentile"] || 0) }.first(3)
      end

      # Build post
      post = "🥅 EDGE STATS: #{goalie_name.upcase}\n\n"

      # Show top save zones if we have them
      if top_zones.any?
        post += "Best save zones:\n"
        top_zones.each do |zone|
          area = zone["area"]
          save_pct = (zone["savePctg"] * 100).round(1) if zone["savePctg"]
          percentile = (zone["savePctgPercentile"] * 100).round(0) if zone["savePctgPercentile"]

          if save_pct && percentile
            post += "• #{area}: #{sprintf("%.1f", save_pct)}% SV (#{percentile}th %ile)\n"
          end
        end
        post += "\n"
      end

      # Always show advanced stats (no percentile threshold)
      if gaa && gaa_percentile
        post += "📊 #{sprintf("%.2f", gaa)} GAA (#{(gaa_percentile * 100).round(0)}th %ile)\n"
      end

      if goal_diff && goal_diff_percentile
        sign = (goal_diff >= 0) ? "+" : ""
        post += "📊 #{sign}#{sprintf("%.2f", goal_diff)} goal diff/60 (#{(goal_diff_percentile * 100).round(0)}th %ile)\n"
      end

      if point_pct && point_pct_percentile
        post += "📊 #{(point_pct * 100).round(1)}% point pct (#{(point_pct_percentile * 100).round(0)}th %ile)\n"
      end

      if games_above_900 && games_above_900_percentile
        post += "📊 #{(games_above_900 * 100).round(0)}% games above .900 (#{(games_above_900_percentile * 100).round(0)}th %ile)\n"
      end

      if sweater_number
        post += "\n##{sweater_number} gets the start tonight."
      end

      post
    end
  end
end
