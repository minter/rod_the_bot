module RodTheBot
  class GameVideoWorker
    require "securerandom"

    include Sidekiq::Worker
    include WorkerErrorHandling

    MAX_RETRIES = 6
    RETRY_INTERVAL = 10.minutes
    VIDEO_TYPES = {
      "threeMinRecap" => {slug: "recap", label: "Game recap"},
      "condensedGame" => {slug: "condensed-game", label: "Condensed game"}
    }.freeze

    def perform(game_id, video_type, retry_count = 0)
      config = VIDEO_TYPES[video_type]
      return discard_job("unknown video type", game_id: game_id, video_type: video_type) unless config

      boxscore = Nhl::GameClient.boxscore(game_id)
      video_id = Nhl::GameClient.right_rail(game_id).dig("gameVideo", video_type)
      return reschedule_unavailable(game_id, video_type, retry_count) if video_id.blank?

      source_url = video_url(boxscore, config[:slug], video_id)
      media = NhlVideoDownloadService.new(source_url, output_path(game_id, video_type, video_id)).call
      post = format_post(boxscore, config[:label])

      if media.start_with?("http://", "https://")
        RodTheBot::Post.perform_async(post, nil, nil, media)
      else
        RodTheBot::Post.perform_async(post, nil, nil, nil, [], media)
      end
    rescue Nhl::RequestError => e
      retry_job(e, game_id: game_id, video_type: video_type, operation: "fetch_game_video")
    rescue => e
      retry_job(e, game_id: game_id, video_type: video_type, operation: "process_game_video")
    end

    private

    def reschedule_unavailable(game_id, video_type, retry_count)
      if retry_count < MAX_RETRIES
        self.class.perform_in(RETRY_INTERVAL, game_id, video_type, retry_count + 1)
      else
        Rails.logger.warn(
          "GameVideoWorker: #{video_type} unavailable for game #{game_id} " \
          "after #{retry_count} retries. Giving up."
        )
      end
    end

    def video_url(boxscore, slug, video_id)
      away = boxscore.dig("awayTeam", "abbrev").to_s.downcase
      home = boxscore.dig("homeTeam", "abbrev").to_s.downcase
      "https://www.nhl.com/video/#{away}-at-#{home}-#{slug}-#{video_id}"
    end

    def output_path(game_id, video_type, video_id)
      filename = "#{video_type.underscore}_#{game_id}_#{video_id}_#{SecureRandom.hex(4)}.mp4"
      Rails.root.join("tmp", filename).to_s
    end

    def format_post(boxscore, label)
      away = team_name(boxscore["awayTeam"])
      home = team_name(boxscore["homeTeam"])
      date = Date.iso8601(boxscore.fetch("gameDate")).strftime("%B %-d, %Y")
      "🎥 #{label}: #{away} at #{home} on #{date}."
    end

    def team_name(team)
      team.dig("placeName", "default") || team["abbrev"]
    end
  end
end
