require "sidekiq"

module RodTheBot
  class DraftPickWorker
    include Sidekiq::Worker

    POST_TTL = 2.days.to_i
    REQUEUE_INTERVAL = 5.minutes
    POST_DELAY = 30.seconds
    BLUESKY_CHARACTER_LIMIT = 300

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
    }.freeze

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

    def perform(year = nil, process_completed = false)
      manual_run = year.present?
      year ||= Date.today.year

      data = NhlApi.fetch_draft_picks(year)

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

      prospects_by_name = index_prospects(NhlApi.fetch_draft_rankings(draft_year))
      picks = data["picks"] || []
      team_abbrev = ENV["NHL_TEAM_ABBREVIATION"] || "CAR"

      picks.each do |pick|
        next unless pick_for_team?(pick, team_abbrev)
        next unless selected_pick?(pick)

        key = draft_pick_key(draft_year, pick)
        next if REDIS.get(key)

        first_name = localized_value(pick["firstName"])
        last_name = localized_value(pick["lastName"])
        ranking_info = prospects_by_name[normalized_name(first_name, last_name)]
        pick_history_str = format_pick_history(pick["teamPickHistory"], team_abbrev)

        post = format_post(pick, ranking_info, pick_history_str, draft_year)
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
          key = normalized_name(prospect["firstName"], prospect["lastName"])
          next if key.blank?

          prospects[key] = prospect.merge("category" => category)
        end
      end
    end

    def pick_for_team?(pick, team_abbrev)
      display_abbrev = localized_value(pick["displayAbbrev"]) || pick["teamAbbrev"]
      display_abbrev == team_abbrev || pick["teamId"].to_s == ENV["NHL_TEAM_ID"].to_s
    end

    def selected_pick?(pick)
      localized_value(pick["firstName"]).present? && localized_value(pick["lastName"]).present?
    end

    def draft_pick_key(draft_year, pick)
      pick_number = pick["overallPick"] || "#{pick["round"]}_#{pick["pickInRound"]}"
      "draft_pick:#{draft_year}:#{pick_number}"
    end

    def format_pick_history(pick_history, team_abbrev)
      teams = pick_history.to_s.split("-").reject(&:blank?)
      return "" if teams.empty? || teams == [team_abbrev]

      original = teams.first
      via = teams[1...-1].to_a.reverse
      return "(from #{original})" if via.empty?

      "(from #{original}, via #{via.join(", ")})"
    end

    def format_post(pick, ranking_info, pick_history_str, draft_year)
      pick_num = pick["overallPick"] || pick["pickInRound"]
      round = pick["round"]
      team_name = localized_value(pick["teamName"])
      position = pick["positionCode"]
      first_name = localized_value(pick["firstName"])
      last_name = localized_value(pick["lastName"])
      club = pick["amateurClubName"]
      league = pick["amateurLeague"]
      country_code = pick["countryCode"]
      demonym = COUNTRY_DEMONYMS[country_code] || country_code

      history_part = pick_history_str.empty? ? "" : " #{pick_history_str}"
      source = [club, league.present? ? "(#{league})" : nil].compact.join(" ")
      source_part = source.present? ? " from #{source}" : ""
      first_line = "📝 With pick No. #{pick_num}#{history_part} in Round #{round} of the #{draft_year} NHL Draft, the #{team_name} selected #{demonym} #{position} #{first_name} #{last_name}#{source_part}."

      details = []
      if ranking_info
        category_name = get_ranking_category_name(ranking_info["category"])
        rank = ranking_info["finalRank"]
        details << "Ranking: #{rank.ordinalize} in #{category_name}" if rank && category_name

        height = ranking_info["heightInInches"]
        details << "Height: #{format_height(height)}" if height

        weight = ranking_info["weightInPounds"]
        details << "Weight: #{weight} lbs" if weight

        shoots_catches_label = (position == "G") ? "Catches" : "Shoots"
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

    def enqueue_post_thread(post, dedupe_key)
      chunks = split_post(post)
      return if chunks.empty?

      if chunks.one?
        RodTheBot::Post.perform_async(chunks.first)
        return
      end

      base_key = "#{dedupe_key}:post"
      first_key = "#{base_key}:1"
      RodTheBot::Post.perform_async(chunks.first, first_key)

      chunks.drop(1).each_with_index do |chunk, index|
        chunk_key = "#{base_key}:#{index + 2}"
        parent_key = (index == 0) ? first_key : "#{base_key}:#{index + 1}"
        RodTheBot::Post.perform_in((index + 1) * POST_DELAY, chunk, chunk_key, parent_key)
      end
    end

    def split_post(post)
      max_length = max_post_length
      chunks = []
      current = ""

      post.split(/\n{2,}/).each do |paragraph|
        paragraph_chunks(paragraph, max_length).each do |piece|
          if current.blank?
            current = piece
          elsif "#{current}\n\n#{piece}".length <= max_length
            current = "#{current}\n\n#{piece}"
          else
            chunks << current
            current = piece
          end
        end
      end

      chunks << current if current.present?
      chunks
    end

    def paragraph_chunks(paragraph, max_length)
      return [paragraph] if paragraph.length <= max_length

      chunks = []
      paragraph.each_line(chomp: true) do |line|
        chunks.concat(wrap_line(line, max_length))
      end
      chunks
    end

    def wrap_line(line, max_length)
      chunks = []
      current = ""

      line.split(/\s+/).each do |word|
        if current.blank?
          current = word
        elsif "#{current} #{word}".length <= max_length
          current = "#{current} #{word}"
        else
          chunks << current
          current = word
        end
      end

      chunks << current if current.present?
      chunks
    end

    def max_post_length
      hashtags = ENV["TEAM_HASHTAGS"].to_s
      hashtag_length = hashtags.empty? ? 0 : hashtags.length + 1
      BLUESKY_CHARACTER_LIMIT - hashtag_length
    end

    def format_height(total_inches)
      total_inches = total_inches.to_i
      return nil unless total_inches.positive?

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
        "north_american_skaters" => "North American Skaters",
        "international_skaters" => "International Skaters",
        "north_american_goalies" => "North American Goalies",
        "international_goalies" => "International Goalies"
      }[category_symbol.to_s]
    end

    def localized_value(value)
      case value
      when Hash
        value["default"] || value.values.compact.first
      else
        value
      end
    end

    def normalized_name(first_name, last_name)
      ActiveSupport::Inflector.transliterate("#{first_name} #{last_name}".downcase).squish
    end
  end
end
