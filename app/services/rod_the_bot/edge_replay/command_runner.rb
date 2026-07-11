require "open3"

module RodTheBot
  module EdgeReplay
    class CommandRunner
      def run(command, label:)
        output, status = Open3.capture2e(*command)
        return if status.success?

        raise "#{label} failed:\n#{output}"
      end
    end
  end
end
