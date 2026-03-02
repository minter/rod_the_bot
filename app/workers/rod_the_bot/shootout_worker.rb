module RodTheBot
  class ShootoutWorker
    include Sidekiq::Worker

    MAX_RETRIES = 30 # ~10 minutes at 20s intervals

    def perform(game_id, retry_count = 0)
      feed = NhlApi.fetch_landing_feed(game_id)
      shootout = feed.dig("summary", "shootout")

      return requeue(game_id, retry_count) if shootout.blank? || shootout["events"].blank?

      events = shootout["events"]
      away_abbrev = feed["awayTeam"]["abbrev"]
      home_abbrev = feed["homeTeam"]["abbrev"]
      game_over = feed["gameState"] == "OFF"

      rounds = group_into_rounds(events)
      rounds_posted = REDIS.get("shootout:#{game_id}:rounds_posted").to_i

      rounds.each_with_index do |round, idx|
        round_num = idx + 1
        next if round_num <= rounds_posted
        next unless round_complete?(round, game_over, idx == rounds.size - 1)

        is_final_round = game_over && idx == rounds.size - 1
        post = format_round(round, round_num, away_abbrev, home_abbrev, is_final_round, shootout["liveScore"])
        post_round(game_id, round_num, post)
        REDIS.set("shootout:#{game_id}:rounds_posted", round_num.to_s, ex: 172800)
      end

      requeue(game_id, retry_count) unless game_over
    rescue NhlApi::APIError => e
      Rails.logger.error "ShootoutWorker: API error for game #{game_id}: #{e.message}. Retrying."
      requeue(game_id, retry_count)
    rescue => e
      Rails.logger.error "ShootoutWorker: Unexpected error for game #{game_id}: #{e.class} - #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      requeue(game_id, retry_count)
    end

    private

    def group_into_rounds(events)
      rounds = []
      current_round = []

      events.each do |event|
        if current_round.empty?
          current_round << event
        elsif event["teamAbbrev"]["default"] != current_round.first["teamAbbrev"]["default"]
          current_round << event
          rounds << current_round
          current_round = []
        else
          rounds << current_round
          current_round = [event]
        end
      end

      rounds << current_round if current_round.any?
      rounds
    end

    def round_complete?(round, game_over, is_last)
      round.size == 2 || (is_last && game_over)
    end

    def format_round(round, round_num, away_abbrev, home_abbrev, is_final_round, live_score)
      lines = ["🏒 Shootout - Round #{round_num}\n"]

      round.each do |event|
        abbrev = event["teamAbbrev"]["default"]
        name = format_shooter_name(event)
        result = (event["result"] == "goal") ? "✅" : "❌"
        lines << "#{abbrev}: #{name} #{result}"
      end

      lines << ""

      if is_final_round
        home_score = live_score["home"]
        away_score = live_score["away"]
        winner_abbrev = (home_score > away_score) ? home_abbrev : away_abbrev
        lines << "#{winner_abbrev} wins the shootout #{[home_score, away_score].max}-#{[home_score, away_score].min}!"
      else
        home_score = round.last["homeScore"]
        away_score = round.last["awayScore"]
        lines << "Shootout: #{away_abbrev} #{away_score}, #{home_abbrev} #{home_score}"
      end

      lines.join("\n") + "\n"
    end

    def format_shooter_name(event)
      first = event["firstName"]["default"]
      last = event["lastName"]["default"]

      # Preserve already-abbreviated names like "J.T."
      initial = first.include?(".") ? first : "#{first[0]}."
      "#{initial} #{last}"
    end

    def post_round(game_id, round_num, post)
      key = "shootout:#{game_id}:round:#{round_num}"

      if round_num == 1
        RodTheBot::Post.perform_async(post, key)
      else
        parent_key = "shootout:#{game_id}:round:#{round_num - 1}"
        RodTheBot::Post.perform_async(post, key, parent_key)
      end
    end

    def requeue(game_id, retry_count)
      if retry_count < MAX_RETRIES
        ShootoutWorker.perform_in(20, game_id, retry_count + 1)
      else
        Rails.logger.warn "ShootoutWorker: Max retries reached for game #{game_id}. Giving up."
      end
    end
  end
end
