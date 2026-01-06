module RodTheBot
  class GoalHighlightWorker
    include Sidekiq::Worker
    include ActiveSupport::Inflector
    include RodTheBot::PeriodFormatter
    include RodTheBot::PlayerFormatter

    def perform(game_id, play_id, redis_key, initial_run_time = nil)
      initial_run_time ||= Time.now.to_i

      # Create a new unique key for this highlight post
      highlight_key = "#{redis_key}:highlight:#{Time.now.to_i}"

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

        # Determine parent_key: Use most recent reply if it exists, otherwise use goal post (root)
        # Threading: Goal (root) -> most recent reply -> next reply -> etc.
        # The Post worker will atomically update last_reply_key after successful posting
        last_reply_tracker_key = "#{redis_key}:last_reply_key"
        last_reply_key = REDIS.get(last_reply_tracker_key)

        # Use last reply as parent if it exists, otherwise use root (goal post)
        parent_key = last_reply_key || redis_key

        if last_reply_key
          Rails.logger.info "GoalHighlightWorker: Replying to most recent reply with key: #{parent_key}"
        else
          Rails.logger.info "GoalHighlightWorker: No previous replies, replying to goal post (root) with key: #{parent_key}"
        end

        # Post as reply - Post worker will update last_reply_key after successful post
        if output_path.include?("http")
          RodTheBot::Post.perform_async(post, highlight_key, parent_key, output_path, [], nil, redis_key)
        else
          RodTheBot::Post.perform_async(post, highlight_key, parent_key, nil, [], output_path, redis_key)
        end
      else
        # Pass redis_key (goal post key) when rescheduling
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
      # Get roster data to find jersey numbers
      players = NhlApi.game_rosters(@pbp_feed["id"])

      # Format scorer with jersey number
      scorer_id = @pbp_play["details"]["scoringPlayerId"]
      scorer_name = format_player_from_roster(players, scorer_id)

      team = landing_play["teamAbbrev"]["default"]
      time = landing_play["timeInPeriod"]
      shot_type = landing_play["shotType"]
      period_name = format_period_name(@pbp_play["periodDescriptor"]["number"])

      # Format assists with jersey numbers
      assist_names = []
      if @pbp_play["details"]["assist1PlayerId"].present?
        assist_names << format_player_from_roster(players, @pbp_play["details"]["assist1PlayerId"])
      end
      if @pbp_play["details"]["assist2PlayerId"].present?
        assist_names << format_player_from_roster(players, @pbp_play["details"]["assist2PlayerId"])
      end

      assist_text = assist_names.empty? ? "" : " Assisted by #{assist_names.join(", ")}."

      away_team = @landing_feed["awayTeam"]["abbrev"]
      home_team = @landing_feed["homeTeam"]["abbrev"]
      score = format("%s %d - %s %d", away_team, landing_play["awayScore"], home_team, landing_play["homeScore"])

      "🎥 Goal highlight: #{scorer_name} (#{team}) scores on a #{shot_type} shot at #{time} of the #{period_name}." \
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
