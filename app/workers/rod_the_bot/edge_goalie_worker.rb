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

      # Post as standalone root post (matchup will reply to this)
      current_date = Time.now.strftime("%Y%m%d")
      post_key = "edge_goalie_#{game_id}:#{current_date}"

      RodTheBot::Post.perform_async(post_text, post_key, nil, nil, [goalie_headshot])
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

      # Get overall stats with percentiles
      gaa = stats.dig("goalsAgainstAvg", "value")
      gaa_percentile = stats.dig("goalsAgainstAvg", "percentile")
      goal_diff = stats.dig("goalDifferentialPer60", "value")
      goal_diff_percentile = stats.dig("goalDifferentialPer60", "percentile")
      point_pct = stats.dig("pointPctg", "value")
      point_pct_percentile = stats.dig("pointPctg", "percentile")

      # Find top save zones (best percentiles, with meaningful sample size)
      top_zones = []
      if shot_details&.any?
        top_zones = shot_details.select do |zone|
          zone["savePctgPercentile"] && zone["saves"] && zone["saves"] > 5
        end.sort_by { |z| -(z["savePctgPercentile"] || 0) }.first(3)
      end

      # Build post - must fit in 300 chars with hashtags (~283 available)
      post = "🥅 EDGE STATS: #{goalie_name.upcase}\n\n"

      # Show top save zones if we have them (compact format)
      if top_zones.any?
        top_zones.each do |zone|
          area = zone["area"]
          save_pct = (zone["savePctg"] * 100).round(1) if zone["savePctg"]
          percentile = (zone["savePctgPercentile"] * 100).round(0) if zone["savePctgPercentile"]

          if save_pct && percentile
            post += "• #{area}: #{sprintf("%.1f", save_pct)}% (#{percentile}th %ile)\n"
          end
        end
        post += "\n"
      end

      # Show key advanced stats (most important 3)
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

      post
    end
  end
end
