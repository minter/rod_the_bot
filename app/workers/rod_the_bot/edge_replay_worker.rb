require "fileutils"

module RodTheBot
  class EdgeReplayWorker
    include Sidekiq::Worker

    def perform(game_id, event_id, redis_key = nil, retry_count = 0)
      Rails.logger.info "EdgeReplayWorker: Generating replay for game #{game_id}, event #{event_id} (attempt #{retry_count + 1})"

      # Create output directory
      output_dir = Rails.root.join("tmp", "edge_replays")
      FileUtils.mkdir_p(output_dir)

      # Check if replay already exists
      output_path = output_dir.join("#{game_id}_#{event_id}_replay.mp4")
      if output_path.exist?
        Rails.logger.info "EdgeReplayWorker: Replay already exists at #{output_path}, skipping generation"
        # If redis_key provided, post the existing replay
        if redis_key
          post_edge_replay(game_id, event_id, output_path.to_s, redis_key)
        end
        return output_path.to_s
      end

      # Download EDGE JSON
      edge_json_path = source.edge_json(game_id, event_id, output_dir)
      unless edge_json_path
        Rails.logger.warn "EdgeReplayWorker: EDGE JSON not available for game #{game_id}, event #{event_id}"
        # Retry if redis_key provided (meaning we want to post it)
        if redis_key && retry_count < 5 # Limit retries to prevent infinite loops
          Rails.logger.info "EdgeReplayWorker: Re-enqueuing in 90 seconds (retry #{retry_count + 1}/5)"
          self.class.perform_in(90.seconds, game_id, event_id, redis_key, retry_count + 1)
        end
        return nil
      end

      # Fetch game data to determine home/away teams and get logos
      game_data = source.game_data(game_id)
      unless game_data
        Rails.logger.warn "EdgeReplayWorker: Game data not available for game #{game_id}"
        # Retry if redis_key provided
        if redis_key && retry_count < 5
          Rails.logger.info "EdgeReplayWorker: Re-enqueuing in 90 seconds (retry #{retry_count + 1}/5)"
          self.class.perform_in(90.seconds, game_id, event_id, redis_key, retry_count + 1)
        end
        return nil
      end

      # Generate MP4
      generate_replay(edge_json_path, output_path, game_data: game_data)

      Rails.logger.info "EdgeReplayWorker: Generated replay at #{output_path}"

      # Post the replay if redis_key provided
      if redis_key
        post_edge_replay(game_id, event_id, output_path.to_s, redis_key)
      end

      output_path.to_s
    rescue => e
      Rails.logger.error "EdgeReplayWorker failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Retry on error if redis_key provided
      if redis_key && retry_count < 5
        Rails.logger.info "EdgeReplayWorker: Re-enqueuing after error in 90 seconds (retry #{retry_count + 1}/5)"
        self.class.perform_in(90.seconds, game_id, event_id, redis_key, retry_count + 1)
      end
      nil
    end

    private

    def generate_replay(input_json_path, output_path, options = {})
      options = renderer.default_options.merge(options)
      generator.generate(input_json_path, output_path, options: options)
    end

    def post_edge_replay(game_id, event_id, video_path, redis_key)
      # Fetch play data to format post text
      pbp_feed = Nhl::GameClient.play_by_play(game_id)
      pbp_play = Nhl::GameClient.play(game_id, event_id)
      return unless pbp_play && pbp_play["typeDescKey"] == "goal"

      # Get roster data
      players = Nhl::GameInfo.roster(game_id)

      # Format post text
      post_text = post_formatter.format(pbp_play, players, pbp_feed)

      # Create a unique key for this EDGE replay post
      edge_replay_key = "#{redis_key}:edge_replay:#{Time.now.to_i}"

      # Determine parent_key: Use most recent reply if it exists, otherwise use goal post (root)
      # Threading: Goal (root) -> most recent reply -> next reply -> etc.
      # The Post worker will atomically update last_reply_key after successful posting
      last_reply_tracker_key = "#{redis_key}:last_reply_key"
      last_reply_key = REDIS.get(last_reply_tracker_key)

      # Use last reply as parent if it exists, otherwise use root (goal post)
      parent_key = last_reply_key || redis_key

      if last_reply_key
        Rails.logger.info "EdgeReplayWorker: Replying to most recent reply with key: #{parent_key}"
      else
        Rails.logger.info "EdgeReplayWorker: No previous replies, replying to goal post (root) with key: #{parent_key}"
      end

      # Post as reply - Post worker will update last_reply_key after successful post
      RodTheBot::Post.perform_async(post_text, edge_replay_key, parent_key, nil, [], video_path, redis_key)
    end

    def post_formatter
      @post_formatter ||= EdgeReplay::PostFormatter.new
    end

    def encoder
      @encoder ||= EdgeReplay::Encoder.new(command_runner: command_runner)
    end

    def generator
      @generator ||= EdgeReplay::Generator.new(renderer: renderer.method(:render), encoder: encoder)
    end

    def command_runner
      @command_runner ||= EdgeReplay::CommandRunner.new
    end

    def renderer
      @renderer ||= EdgeReplay::Renderer.new(source: source, command_runner: command_runner)
    end

    def source
      @source ||= EdgeReplay::Source.new
    end
  end
end
