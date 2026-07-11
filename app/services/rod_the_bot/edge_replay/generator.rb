require "json"
require "fileutils"
require "tmpdir"

module RodTheBot
  module EdgeReplay
    class Generator
      def initialize(renderer:, encoder: Encoder.new)
        @renderer = renderer
        @encoder = encoder
      end

      def generate(input_path, output_path, options:)
        frames = JSON.parse(File.read(input_path))
        selected = select_frames(frames, options)
        return unless selected.any?

        Dir.mktmpdir("edge_replay_") do |directory|
          frames_dir = File.join(directory, "frames")
          FileUtils.mkdir_p(frames_dir)
          renderer.call(selected, options, frames_dir, directory)

          video = File.join(directory, "video.mp4")
          encoder.encode(frames_dir, video, fps: options[:fps])
          FileUtils.mv(video, output_path)
        end
        output_path
      end

      private

      attr_reader :renderer, :encoder

      def select_frames(frames, options)
        return [] unless frames.is_a?(Array) && frames.any?

        start = [options[:start].to_i, 0].max
        finish = options[:frames] ? [start + options[:frames].to_i, frames.length].min : frames.length
        frames[start...finish] || []
      end
    end
  end
end
