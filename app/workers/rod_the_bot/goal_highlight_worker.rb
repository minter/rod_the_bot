module RodTheBot
  class GoalHighlightWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter

    def perform(game_id, play_id, redis_key, initial_run_time = nil)
      initial_run_time ||= Time.now.to_i

      # Add timestamp to redis key to ensure uniqueness
      redis_key = "#{redis_key}:#{Time.now.strftime("%Y%m%d")}" if redis_key

      # Check if 6 hours have passed since the initial run
      if Time.now.to_i - initial_run_time > 6.hours.to_i
        logger.info "Job for game_id: #{game_id}, play_id: #{play_id} exceeded 6 hours limit. Exiting."
        return
      end

      @pbp_feed = NhlApi.fetch_pbp_feed(game_id)
      @landing_feed = NhlApi.fetch_landing_feed(game_id)
      @pbp_play = NhlApi.fetch_play(game_id, play_id)

      return if @pbp_play.blank? || @pbp_play["typeDescKey"] != "goal"

      @landing_play = find_matching_goal(@pbp_play)

      return if @landing_play.blank?

      if @landing_play["highlightClipSharingUrl"].present?
        output_path = download_highlight(@landing_play["highlightClipSharingUrl"])
        post = format_post(@landing_play)
        if output_path.include?("http")
          RodTheBot::Post.perform_async(post, redis_key, nil, output_path, [], nil)
        else
          RodTheBot::Post.perform_async(post, redis_key, nil, nil, [], output_path)
        end
      else
        self.class.perform_in(3.minutes, game_id, play_id, redis_key, initial_run_time)
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
      scorer_full_name = "#{landing_play["firstName"]["default"]} #{landing_play["lastName"]["default"]}"
      team = landing_play["teamAbbrev"]["default"]
      time = landing_play["timeInPeriod"]
      shot_type = landing_play["shotType"]
      period_name = format_period_name(@pbp_play["periodDescriptor"]["number"])

      assists = landing_play["assists"].map { |a| "#{a["firstName"]["default"]} #{a["lastName"]["default"]}" }
      assist_text = assists.empty? ? "" : " Assisted by #{assists.join(", ")}."

      away_team = @landing_feed["awayTeam"]["abbrev"]
      home_team = @landing_feed["homeTeam"]["abbrev"]
      score = format("%s %d - %s %d", away_team, landing_play["awayScore"], home_team, landing_play["homeScore"])

      "🎥 Goal highlight: #{scorer_full_name} (#{team}) scores on a #{shot_type} shot at #{time} of the #{period_name}." \
      "#{assist_text} Score: #{score}"
    end

    def download_highlight(url, output_path = nil)
      filename = url.match(/\d+$/).present? ? "highlight_#{url.match(/\d+$/)[0]}.mp4" : "highlight.mp4"
      service = NhlVideoDownloadService.new(
        url,
        "#{Rails.root}/tmp/#{filename}" # optional
      )

      begin
        service.call
      rescue => e
        # Handle errors
        logger.error "Error downloading highlight: #{e.message}"
      end
    end
  end
end
