module Nhl
  class Client
    include HTTParty

    class << self
      private

      def get_json(path)
        response = get(path)
        raise RequestError, "API request failed: #{response.code}" unless response.success?

        response.parsed_response
      rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
        raise RequestError, "Network error fetching #{path}: #{e.class} - #{e.message}"
      end
    end
  end
end
