require "sidekiq"

module RodTheBot
  class DraftPickWorker
    include Sidekiq::Worker

    POST_TTL = 2.days.to_i
    REQUEUE_INTERVAL = 5.minutes
    POST_DELAY = 30.seconds
    BLUESKY_CHARACTER_LIMIT = 300

    def perform(year = nil, process_completed = false)
      manual_run = year.present?
      year ||= Date.today.year

      data = Nhl::DraftClient.picks(year)

      unless data.is_a?(Hash)
        Sidekiq.logger.error "Failed to fetch or parse draft data for year #{year}"
        return
      end

      draft_year = data["draftYear"] || year
      unless manual_run || draft_day?(data, draft_year)
        Sidekiq.logger.info "Not a draft day (#{Date.today.strftime("%Y-%m-%d")}), skipping."
        return
      end

      state = data["state"]
      if state == "fut"
        Sidekiq.logger.info "Draft not started yet (state: fut)."
        requeue_for_live_monitoring unless manual_run
        return
      elsif state == "over"
        if process_completed
          Sidekiq.logger.info "Draft is over (state: over), but process_completed is true. Processing picks."
        else
          Sidekiq.logger.info "Draft is over (state: over), nothing to do."
          return
        end
      end

      prospects_by_name = index_prospects(Nhl::DraftClient.rankings(draft_year))
      picks = data["picks"] || []
      team_abbrev = ENV["NHL_TEAM_ABBREVIATION"] || "CAR"

      picks.each do |pick|
        next unless pick_for_team?(pick, team_abbrev)
        next unless selected_pick?(pick)

        key = draft_pick_key(draft_year, pick)
        next if REDIS.get(key)

        first_name = formatter.localized(pick["firstName"])
        last_name = formatter.localized(pick["lastName"])
        ranking_info = prospects_by_name[formatter.normalized_name(first_name, last_name)]
        pick_history_str = formatter.pick_history(pick["teamPickHistory"], team_abbrev)

        post = formatter.format(pick, ranking: ranking_info, history: pick_history_str, year: draft_year)
        enqueue_post_thread(post, key)

        REDIS.set(key, "1", ex: POST_TTL)
        Sidekiq.logger.info "Posted: #{post}"
      end

      requeue_for_live_monitoring unless manual_run
    end

    private

    def draft_day?(data, draft_year)
      today = Date.today.strftime("%Y-%m-%d")
      active_dates = inferred_active_dates(data)

      active_dates.include?(today) || (data["state"].present? && data["state"] != "fut" && draft_year.to_i == Date.today.year)
    end

    def inferred_active_dates(data)
      broadcast_time = data["broadcastStartTimeUTC"]
      return [] if broadcast_time.blank?

      draft_start_date = Time.zone.parse(broadcast_time).to_date
      [draft_start_date, draft_start_date + 1.day].map { |date| date.strftime("%Y-%m-%d") }
    end

    def requeue_for_live_monitoring
      self.class.perform_in(REQUEUE_INTERVAL)
    end

    def index_prospects(rankings)
      return {} unless rankings.respond_to?(:each)

      rankings.each_with_object({}) do |(category, prospect_list), prospects|
        Array(prospect_list).each do |prospect|
          key = formatter.normalized_name(prospect["firstName"], prospect["lastName"])
          next if key.blank?

          prospects[key] = prospect.merge("category" => category)
        end
      end
    end

    def pick_for_team?(pick, team_abbrev)
      display_abbrev = formatter.localized(pick["displayAbbrev"]) || pick["teamAbbrev"]
      display_abbrev == team_abbrev || pick["teamId"].to_s == ENV["NHL_TEAM_ID"].to_s
    end

    def selected_pick?(pick)
      formatter.localized(pick["firstName"]).present? && formatter.localized(pick["lastName"]).present?
    end

    def draft_pick_key(draft_year, pick)
      pick_number = pick["overallPick"] || "#{pick["round"]}_#{pick["pickInRound"]}"
      "draft_pick:#{draft_year}:#{pick_number}"
    end

    def enqueue_post_thread(post, dedupe_key)
      chunks = PostThread.split(post)
      PostThread.enqueue(chunks, key: "#{dedupe_key}:post", delay: POST_DELAY)
    end

    def formatter
      @formatter ||= DraftPick::Formatter.new
    end
  end
end
