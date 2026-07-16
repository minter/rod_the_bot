module Nhl
  class Client
    include HTTParty

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    class << self
      private

      def get_json(path)
        response = get(path, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
        unless response.success?
          raise RequestError, "API request failed for #{path}: HTTP #{response.code}"
        end

        response.parsed_response
      rescue JSON::ParserError => e
        raise RequestError, "Invalid JSON fetching #{path}: #{e.class} - #{e.message}"
      rescue Timeout::Error, SocketError,
        Errno::ECONNREFUSED, Errno::ECONNRESET, EOFError => e
        raise RequestError, "Network error fetching #{path}: #{e.class} - #{e.message}"
      end
    end
  end
end
