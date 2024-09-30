module RodTheBot
  class GoalHighlightWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter

    def perform(game_id, play_id)
      @pbp_feed = NhlApi.fetch_pbp_feed(game_id)
      @landing_feed = NhlApi.fetch_landing_feed(game_id)
      @pbp_play = NhlApi.fetch_play(game_id, play_id)

      return if @pbp_play.blank? || @pbp_play["typeDescKey"] != "goal"

      @landing_play = find_matching_goal(@pbp_play)

      return if @landing_play.blank?

      if @landing_play["highlightClipSharingUrl"].present?
        post = format_post(@landing_play)
        RodTheBot::Post.perform_async(post, "#{game_id}:#{play_id}", @landing_play["highlightClipSharingUrl"])
      else
        RodTheBot::GoalHighlightWorker.perform_in(30.seconds, game_id, play_id)
      end
    end

    private

    def find_matching_goal(pbp_play)
      period = pbp_play["periodDescriptor"]["number"]
      time = pbp_play["timeInPeriod"]

      @landing_feed["summary"]["scoring"].find do |scoring_period|
        scoring_period["periodDescriptor"]["number"] == period
      end&.dig("goals")&.find do |goal|
        goal["timeInPeriod"] == time
      end
    end

    def format_post(landing_play)
      scorer_first_name = landing_play["firstName"]["default"]
      scorer_last_name = landing_play["lastName"]["default"]
      scorer_full_name = "#{scorer_first_name} #{scorer_last_name}"
      team = landing_play["teamAbbrev"]["default"]
      time = landing_play["timeInPeriod"]
      away_score = landing_play["awayScore"]
      home_score = landing_play["homeScore"]
      shot_type = landing_play["shotType"]
      period_name = format_period_name(@pbp_play["periodDescriptor"]["number"])

      assists = landing_play["assists"].map do |a|
        "#{a["firstName"]["default"]} #{a["lastName"]["default"]}"
      end.join(", ")

      assist_text = assists.present? ? " Assisted by #{assists}." : ""

      "🎥 Goal highlight: #{scorer_full_name} (#{team}) scores on a #{shot_type} shot at #{time} of the #{period_name}. #{assist_text} Score: #{away_score}-#{home_score}"
    end
  end
end