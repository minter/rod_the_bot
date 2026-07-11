require "test_helper"

class RodTheBot::EdgeReplay::GeneratorTest < ActiveSupport::TestCase
  test "returns nil for an empty frame collection" do
    input = Tempfile.new(["edge-frames", ".json"])
    input.write("[]")
    input.close
    renderer = mock("renderer")
    renderer.expects(:call).never

    result = RodTheBot::EdgeReplay::Generator.new(renderer: renderer).generate(
      input.path, "/tmp/output.mp4", options: {start: 0, frames: nil, fps: 30}
    )

    assert_nil result
  ensure
    input&.unlink
  end
end
