require "test_helper"

class Nhl::ClientTest < ActiveSupport::TestCase
  test "uses explicit connection and response timeouts" do
    response = stub(success?: true, parsed_response: {"ok" => true})
    Nhl::Client.expects(:get).with(
      "/resource",
      open_timeout: Nhl::Client::OPEN_TIMEOUT,
      read_timeout: Nhl::Client::READ_TIMEOUT
    ).returns(response)

    assert_equal({"ok" => true}, Nhl::Client.send(:get_json, "/resource"))
  end

  test "normalizes unsuccessful responses with endpoint context" do
    Nhl::Client.stubs(:get).returns(stub(success?: false, code: 503))

    error = assert_raises(Nhl::RequestError) do
      Nhl::Client.send(:get_json, "/resource")
    end

    assert_equal "API request failed for /resource: HTTP 503", error.message
  end

  test "normalizes network failures with endpoint context" do
    Nhl::Client.stubs(:get).raises(Net::ReadTimeout, "execution expired")

    error = assert_raises(Nhl::RequestError) do
      Nhl::Client.send(:get_json, "/resource")
    end

    assert_match "Network error fetching /resource", error.message
    assert_match "Net::ReadTimeout", error.message
  end

  test "normalizes malformed JSON with endpoint context" do
    response = stub(success?: true)
    response.stubs(:parsed_response).raises(JSON::ParserError, "unexpected token")
    Nhl::Client.stubs(:get).returns(response)

    error = assert_raises(Nhl::RequestError) do
      Nhl::Client.send(:get_json, "/resource")
    end

    assert_match "Invalid JSON fetching /resource", error.message
  end
end
