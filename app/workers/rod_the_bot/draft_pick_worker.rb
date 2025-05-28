require "sidekiq"

module RodTheBot
  class DraftPickWorker
    include Sidekiq::Worker

    COUNTRY_DEMONYMS = {
      "CAN" => "Canadian",
      "USA" => "American",
      "CZE" => "Czech",
      "SWE" => "Swedish",
      "FIN" => "Finnish",
      "RUS" => "Russian",
      "CHE" => "Swiss",
      "SVK" => "Slovak",
      "DEU" => "German",
      "NOR" => "Norwegian",
      "LVA" => "Latvian",
      "BLR" => "Belarusian",
      "DNK" => "Danish",
      "SVN" => "Slovenian",
      "AUT" => "Austrian",
      "CHN" => "Chinese",
      "ZAF" => "South African",
      "KAZ" => "Kazakh",
      "FRA" => "French",
      "EST" => "Estonian",
      "POL" => "Polish",
      "HUN" => "Hungarian",
      "UKR" => "Ukrainian",
      "NLD" => "Dutch",
      "ITA" => "Italian",
      "JPN" => "Japanese",
      "AUS" => "Australian",
      "GBR" => "British",
      "IRL" => "Irish",
      "LTU" => "Lithuanian",
      "ROU" => "Romanian",
      "CRO" => "Croatian",
      "ESP" => "Spanish",
      "POR" => "Portuguese",
      "NZL" => "New Zealander"
      # Add more as needed
    }

    def perform
      # 1. Check if today is an active draft date
      active_dates = ENV["DRAFT_ACTIVE_DATES"].to_s.split(",")
      today = Date.today.strftime("%Y-%m-%d")
      draft_day = active_dates.include?(today) || ENV["DRAFT_YEAR_OVERRIDE"].present?
      unless draft_day
        Sidekiq.logger.info "Not a draft day (#{today}), skipping."
        return
      end

      # 2. Determine draft year
      year = ENV["DRAFT_YEAR_OVERRIDE"].presence || Date.today.year

      # 3. Fetch draft data
      data = NhlApi.fetch_draft_picks(year)
      unless data.is_a?(Hash) && data["picks"].is_a?(Array)
        Sidekiq.logger.error "Failed to fetch or parse draft data for year #{year}"
        return
      end

      # 4. Check draft state
      state = data["state"]
      if state == "fut"
        Sidekiq.logger.info "Draft not started yet (state: fut)."
        # Only requeue if today is a draft day
        if draft_day
          self.class.perform_in(5 * 60) # Re-queue in 5 minutes
        end
        return
      elsif state == "over"
        if ENV["DRAFT_YEAR_OVERRIDE"].present?
          Sidekiq.logger.info "Draft is over (state: over), but DRAFT_YEAR_OVERRIDE is set. Processing picks for testing."
          # Do not requeue at the end
        else
          Sidekiq.logger.info "Draft is over (state: over), nothing to do."
          return
        end
      end

      picks = data["picks"] || []
      team_abbrev = ENV["NHL_TEAM_ABBREVIATION"] || "CAR"

      picks.each do |pick|
        # Only process picks for our team
        display_abbrev = pick.dig("displayAbbrev", "default") || pick["displayAbbrev"]
        next unless display_abbrev == team_abbrev

        # Deduplication key
        key = "draft_pick_#{year}_#{pick["round"]}_#{pick["pickInRound"]}"
        next if REDIS.get(key)

        # Build pick history string
        pick_history = pick["teamPickHistory"]
        pick_history_str = ""
        if pick_history && pick_history != team_abbrev
          teams = pick_history.split("-")
          if teams.size == 2
            pick_history_str = "(from #{teams.first})"
          elsif teams.size > 2
            original = teams.first
            via = teams[1..-2].reverse
            pick_history_str = "(from #{original}, via #{via.join(", ")})"
          end
        end

        # Compose post
        pick_num = pick["pickInRound"]
        round = pick["round"]
        draft_year = data["draftYear"] || year
        team_name = pick.dig("teamName", "default") || pick["teamName"]
        position = pick["positionCode"]
        first_name = pick.dig("firstName", "default") || pick["firstName"]
        last_name = pick.dig("lastName", "default") || pick["lastName"]
        club = pick["amateurClubName"]
        country_code = pick["countryCode"]
        demonym = COUNTRY_DEMONYMS[country_code] || country_code

        post = "📝 With pick #{pick_num} #{pick_history_str} in round #{round} of the #{draft_year} NHL Draft, the #{team_name} have selected #{demonym} #{position} #{first_name} #{last_name} (#{club}, #{country_code})"

        # Post to Bluesky
        RodTheBot::Post.perform_async(post, key)

        # Store key in Redis for deduplication
        REDIS.set(key, "1", ex: 2 * 24 * 60 * 60) # 2 days TTL

        Sidekiq.logger.info "Posted: #{post}"
      end

      # If today is a draft day, always requeue for live monitoring
      # But do NOT requeue if DRAFT_YEAR_OVERRIDE is set (testing mode)
      if draft_day && ENV["DRAFT_YEAR_OVERRIDE"].blank?
        self.class.perform_in(5 * 60) # Re-queue in 5 minutes
      end
    end
  end
end
