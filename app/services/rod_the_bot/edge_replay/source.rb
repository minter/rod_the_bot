require "net/http"
require "uri"

module RodTheBot
  module EdgeReplay
    class Source
      def edge_json(game_id, event_id, output_dir)
        season = season_slug(game_id)
        url = "https://wsr.nhle.com/sprites/#{season}/#{game_id}/ev#{event_id}.json"
        path = output_dir.join("#{game_id}_ev#{event_id}.json")
        response = request(url, headers: edge_headers(game_id))
        return unless response

        File.binwrite(path, response.body)
        path
      rescue => e
        Rails.logger.error "Error downloading EDGE JSON: #{e.message}"
        nil
      end

      def game_data(game_id)
        data = Nhl::GameClient.landing(game_id)
        data if data&.dig("homeTeam") && data.dig("awayTeam")
      rescue => e
        Rails.logger.error "Error fetching game data: #{e.message}"
        nil
      end

      def team_logo(url, directory)
        return unless url

        abbreviation = url.match(%r{/([A-Z]+)_})&.[](1)
        return unless abbreviation

        path = File.join(directory, "#{abbreviation}_logo.svg")
        return path if File.exist?(path)

        response = request(url)
        return unless response

        File.binwrite(path, response.body)
        path
      rescue => e
        Rails.logger.error "Error downloading team logo: #{e.message}"
        nil
      end

      private

      def request(url, headers: {})
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        request = Net::HTTP::Get.new(uri.request_uri)
        request["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
        headers.each { |name, value| request[name] = value }
        response = http.request(request)
        return response if response.is_a?(Net::HTTPSuccess)

        Rails.logger.error "Failed to download #{url}: HTTP #{response.code}"
        nil
      end

      def edge_headers(game_id)
        {
          "Accept" => "application/json,*/*;q=0.8",
          "Origin" => "https://www.nhl.com",
          "Referer" => "https://www.nhl.com/gamecenter/#{game_id}/playbyplay",
          "Sec-Fetch-Site" => "cross-site",
          "Sec-Fetch-Mode" => "cors",
          "Sec-Fetch-Dest" => "empty"
        }
      end

      def season_slug(game_id)
        value = game_id.to_s.strip
        raise ArgumentError, "Invalid game_id" unless value.match?(/\A\d{10}\z/)

        year = value.first(4).to_i
        "#{year}#{year + 1}"
      end
    end
  end
end
