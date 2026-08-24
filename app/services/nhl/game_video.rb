module Nhl
  class GameVideo
    UnknownType = Class.new(ArgumentError)
    MalformedVideo = Class.new(StandardError)

    Video = Data.define(:id, :type, :source_url, :label, :away_name, :home_name, :date)

    TYPES = {
      "threeMinRecap" => {slug: "recap", label: "Game recap"},
      "condensedGame" => {slug: "condensed-game", label: "Condensed game"}
    }.freeze

    class << self
      def find(game_id, type)
        config = TYPES[type]
        raise UnknownType, "unknown video type: #{type}" unless config

        video_id = GameClient.right_rail(game_id).dig("gameVideo", type)
        return if video_id.blank?

        normalize(GameClient.boxscore(game_id), type, video_id, config)
      end

      private

      def normalize(boxscore, type, video_id, config)
        away = boxscore.fetch("awayTeam", {})
        home = boxscore.fetch("homeTeam", {})
        away_abbrev = away["abbrev"].presence
        home_abbrev = home["abbrev"].presence
        game_date = boxscore["gameDate"].presence
        unless away_abbrev && home_abbrev && game_date
          raise MalformedVideo, "missing team abbreviation or game date for video #{video_id}"
        end

        Video.new(
          id: video_id,
          type: type,
          source_url: source_url(away_abbrev, home_abbrev, config[:slug], video_id),
          label: config[:label],
          away_name: team_name(away),
          home_name: team_name(home),
          date: Date.iso8601(game_date)
        )
      rescue Date::Error => e
        raise MalformedVideo, "invalid game date for video #{video_id}: #{e.message}"
      end

      def source_url(away_abbrev, home_abbrev, slug, video_id)
        "https://www.nhl.com/video/#{away_abbrev.downcase}-at-#{home_abbrev.downcase}-#{slug}-#{video_id}"
      end

      def team_name(team)
        team.dig("placeName", "default").presence || team.fetch("abbrev")
      end
    end
  end
end
