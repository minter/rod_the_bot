require "test_helper"

class RodTheBot::EdgeReplay::EncoderTest < ActiveSupport::TestCase
  test "encodes numbered PNG frames to a web-compatible MP4" do
    runner = mock("command runner")
    runner.expects(:run).with do |command, label:|
      label == "ffmpeg encode" && command.include?("libx264") && command.include?("/tmp/output.mp4")
    end

    RodTheBot::EdgeReplay::Encoder.new(command_runner: runner).encode("/tmp/frames", "/tmp/output.mp4", fps: 30)
  end
end
