module RodTheBot
  module EdgeReplay
    class Encoder
      def initialize(command_runner: CommandRunner.new)
        @command_runner = command_runner
      end

      def encode(frames_dir, output_path, fps:)
        command_runner.run(
          ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-framerate", fps.to_s,
            "-i", File.join(frames_dir, "frame_%05d.png"), "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", output_path],
          label: "ffmpeg encode"
        )
      end

      private

      attr_reader :command_runner
    end
  end
end
