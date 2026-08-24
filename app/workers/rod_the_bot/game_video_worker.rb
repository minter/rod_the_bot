module RodTheBot
  class GameVideoWorker
    require "securerandom"

    include Sidekiq::Worker
    include WorkerErrorHandling

    MAX_RETRIES = 6
    RETRY_INTERVAL = 10.minutes

    def perform(game_id, video_type, retry_count = 0)
      media = nil
      video = Nhl::GameVideo.find(game_id, video_type)
      return reschedule_unavailable(game_id, video_type, retry_count) unless video

      media = NhlVideoDownloadService.new(
        video.source_url,
        output_path(game_id, video.type, video.id)
      ).call
      post = RodTheBot::GameVideo::PostFormatter.new.format(video)

      if media.attachment?
        RodTheBot::Post.perform_async(post, {"video_file_path" => media.attachment_path})
      else
        RodTheBot::Post.perform_async(post, {"embed_url" => media.fallback_url})
      end
    rescue Nhl::GameVideo::UnknownType, Nhl::GameVideo::MalformedVideo => e
      discard_job(e.message, game_id: game_id, video_type: video_type)
    rescue Nhl::RequestError => e
      retry_job(e, game_id: game_id, video_type: video_type, operation: "fetch_game_video")
    rescue => e
      cleanup_unenqueued_media(media)
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

    def output_path(game_id, video_type, video_id)
      filename = "#{video_type.underscore}_#{game_id}_#{video_id}_#{SecureRandom.hex(4)}.mp4"
      Rails.root.join("tmp", filename).to_s
    end

    def cleanup_unenqueued_media(media)
      path = media&.attachment_path
      File.unlink(path) if path && File.exist?(path)
    rescue => e
      Rails.logger.warn "GameVideoWorker: Failed to clean up unqueued media #{path}: #{e.message}"
    end
  end
end
