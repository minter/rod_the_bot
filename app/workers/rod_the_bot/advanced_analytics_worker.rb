module RodTheBot
  class AdvancedAnalyticsWorker
    include Sidekiq::Worker
    include ActionView::Helpers::TextHelper

    def perform(game_id, period_number = nil)
      @game_id = game_id
      @period_number = period_number
      @feed = NhlApi.fetch_landing_feed(game_id)
      return unless @feed

      analytics_data = calculate_advanced_metrics
      return if analytics_data.empty?

      post_analytics(analytics_data)
    end

    private

    def calculate_advanced_metrics
      # Get shift charts for advanced metrics
      shift_data = get_shift_charts
      return {} if shift_data.empty?

      your_team_id = ENV["NHL_TEAM_ID"].to_i
      your_team_shifts = shift_data.select { |shift| shift["teamId"] == your_team_id }
      opponent_shifts = shift_data.reject { |shift| shift["teamId"] == your_team_id }

      {
        corsi_for: calculate_corsi(your_team_shifts),
        corsi_against: calculate_corsi(opponent_shifts),
        fenwick_for: calculate_fenwick(your_team_shifts),
        fenwick_against: calculate_fenwick(opponent_shifts),
        high_danger_chances: calculate_high_danger_chances(your_team_shifts),
        expected_goals: calculate_expected_goals(your_team_shifts)
      }
    end

    def get_shift_charts
      Rails.cache.fetch("shift_charts_#{@game_id}_#{@period_number}", expires_in: 1.hour) do
        response = HTTParty.get("https://api.nhle.com/stats/rest/en/shiftcharts?cayenneExp=gameId=#{@game_id}")
        return [] unless response.success?

        response.parsed_response["data"] || []
      end
    end

    def calculate_corsi(shifts)
      # Corsi = shots on goal + shots that missed + shots that were blocked
      # This is a simplified calculation using available data
      shifts.sum { |shift| (shift["shotsFor"] || 0) + (shift["missedShots"] || 0) + (shift["blockedShots"] || 0) }
    end

    def calculate_fenwick(shifts)
      # Fenwick = shots on goal + shots that missed (excludes blocked shots)
      shifts.sum { |shift| (shift["shotsFor"] || 0) + (shift["missedShots"] || 0) }
    end

    def calculate_high_danger_chances(shifts)
      # High-danger chances are typically defined as shots from the slot area
      # This would require more detailed shot location data
      shifts.sum { |shift| shift["highDangerShots"] || 0 }
    end

    def calculate_expected_goals(shifts)
      # Expected goals based on shot quality and location
      # This would require shot location and quality data
      shifts.sum { |shift| shift["expectedGoals"] || 0 }
    end

    def post_analytics(data)
      period_text = @period_number ? " (Period #{@period_number})" : ""

      post_content = "📊 Advanced Analytics#{period_text}:\n\n"

      # Calculate percentages
      total_corsi = data[:corsi_for] + data[:corsi_against]
      total_fenwick = data[:fenwick_for] + data[:fenwick_against]

      corsi_pct = (total_corsi > 0) ? (data[:corsi_for].to_f / total_corsi * 100).round(1) : 0
      fenwick_pct = (total_fenwick > 0) ? (data[:fenwick_for].to_f / total_fenwick * 100).round(1) : 0

      post_content += "Corsi: #{data[:corsi_for]}-#{data[:corsi_against]} (#{corsi_pct}%)\n"
      post_content += "Fenwick: #{data[:fenwick_for]}-#{data[:fenwick_against]} (#{fenwick_pct}%)\n"

      if data[:high_danger_chances] > 0
        post_content += "High-Danger Chances: #{data[:high_danger_chances]}\n"
      end

      if data[:expected_goals] > 0
        post_content += "Expected Goals: #{data[:expected_goals].round(2)}\n"
      end

      RodTheBot::Post.perform_async(post_content)
    end
  end
end
