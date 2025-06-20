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

    COUNTRY_NAMES = {
      "CAN" => "Canada",
      "USA" => "USA",
      "CZE" => "Czech Republic",
      "SWE" => "Sweden",
      "FIN" => "Finland",
      "RUS" => "Russia",
      "CHE" => "Switzerland",
      "SVK" => "Slovakia",
      "DEU" => "Germany"
    }.freeze

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
      rankings = NhlApi.fetch_draft_rankings(year)

      unless data.is_a?(Hash)
        Sidekiq.logger.error "Failed to fetch or parse draft data for year #{year}"
        return
      end

      prospects_by_name = {}
      rankings.each do |category, prospect_list|
        prospect_list.each do |prospect|
          full_name = "#{prospect["firstName"]} #{prospect["lastName"]}"
          prospects_by_name[full_name] = prospect.merge("category" => category)
        end
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

      draft_year = data["draftYear"] || year
      picks = data["picks"] || []
      team_abbrev = ENV["NHL_TEAM_ABBREVIATION"] || "CAR"

      picks.each do |pick|
        # Only process picks for our team
        display_abbrev = pick.dig("displayAbbrev", "default") || pick["displayAbbrev"]
        next unless display_abbrev == team_abbrev

        # Deduplication key
        key = "draft_pick_#{year}_#{pick["round"]}_#{pick["pickInRound"]}"
        # next if REDIS.get(key)

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
        first_name = pick.dig("firstName", "default") || pick["firstName"]
        last_name = pick.dig("lastName", "default") || pick["lastName"]
        ranking_info = prospects_by_name["#{first_name} #{last_name}"]

        post = format_post(pick, ranking_info, pick_history_str, draft_year)

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

    private

    def format_post(pick, ranking_info, pick_history_str, draft_year)
      # Data from pick
      pick_num = pick["pickInRound"]
      round = pick["round"]
      team_name = pick.dig("teamName", "default") || pick["teamName"]
      position = pick["positionCode"]
      first_name = pick.dig("firstName", "default") || pick["firstName"]
      last_name = pick.dig("lastName", "default") || pick["lastName"]
      club = pick["amateurClubName"]
      league = pick["amateurLeague"]
      country_code = pick["countryCode"]
      demonym = COUNTRY_DEMONYMS[country_code] || country_code

      # First line
      history_part = pick_history_str.empty? ? "" : " #{pick_history_str}"
      first_line = "📝 With the #{pick_num.ordinalize} pick#{history_part} in round #{round} of the #{draft_year} NHL Draft, the #{team_name} have selected #{demonym} #{position} #{first_name} #{last_name} from #{club} (#{league})"

      # Details
      details = []
      if ranking_info
        category_name = get_ranking_category_name(ranking_info["category"])
        rank = ranking_info["finalRank"]
        details << "Ranking: #{rank.ordinalize} in #{category_name}"

        height = ranking_info["heightInInches"]
        details << "Height: #{format_height(height)}" if height

        weight = ranking_info["weightInPounds"]
        details << "Weight: #{weight} lbs" if weight

        shoots_catches_label = position == "G" ? "Catches" : "Shoots"
        shoots_catches = ranking_info["shootsCatches"]
        details << "#{shoots_catches_label}: #{shoots_catches}" if shoots_catches

        birth_date = ranking_info["birthDate"]
        details << "Birthday: #{Date.parse(birth_date).strftime("%m/%d/%Y")}" if birth_date

        birthplace = format_birthplace(ranking_info)
        details << "Birthplace: #{birthplace}" if birthplace.present?
      else # unranked
        details << "Ranking: Unranked"
        height = pick["height"]
        details << "Height: #{format_height(height)}" if height
        weight = pick["weight"]
        details << "Weight: #{weight} lbs" if weight
      end

      [first_line, details.join("\n")].join("\n\n")
    end

    def format_height(total_inches)
      return nil unless total_inches.is_a?(Numeric) && total_inches.positive?

      feet = total_inches / 12
      inches = total_inches % 12
      "#{feet}'#{inches}\""
    end

    def format_birthplace(ranking_info)
      city = ranking_info["birthCity"]
      province = ranking_info["birthStateProvince"]
      country_code = ranking_info["birthCountry"]

      if province.present?
        "#{city}, #{province}"
      elsif city.present? && country_code.present?
        "#{city}, #{COUNTRY_NAMES[country_code] || country_code}"
      else
        city
      end
    end

    def get_ranking_category_name(category_symbol)
      {
        north_american_skaters: "North American Skaters",
        international_skaters: "International Skaters",
        north_american_goalies: "North American Goalies",
        international_goalies: "International Goalies"
      }[category_symbol]
    end
  end
end
