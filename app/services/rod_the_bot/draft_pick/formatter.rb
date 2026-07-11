module RodTheBot
  module DraftPick
    class Formatter
      DEMONYMS = {"CAN" => "Canadian", "USA" => "American", "CZE" => "Czech", "SWE" => "Swedish", "FIN" => "Finnish", "RUS" => "Russian", "CHE" => "Swiss", "SVK" => "Slovak", "DEU" => "German", "NOR" => "Norwegian", "LVA" => "Latvian", "BLR" => "Belarusian", "DNK" => "Danish", "SVN" => "Slovenian", "AUT" => "Austrian", "CHN" => "Chinese", "ZAF" => "South African", "KAZ" => "Kazakh", "FRA" => "French", "EST" => "Estonian", "POL" => "Polish", "HUN" => "Hungarian", "UKR" => "Ukrainian", "NLD" => "Dutch", "ITA" => "Italian", "JPN" => "Japanese", "AUS" => "Australian", "GBR" => "British", "IRL" => "Irish", "LTU" => "Lithuanian", "ROU" => "Romanian", "CRO" => "Croatian", "ESP" => "Spanish", "POR" => "Portuguese", "NZL" => "New Zealander"}.freeze
      COUNTRIES = {"CAN" => "Canada", "USA" => "USA", "CZE" => "Czech Republic", "SWE" => "Sweden", "FIN" => "Finland", "RUS" => "Russia", "CHE" => "Switzerland", "SVK" => "Slovakia", "DEU" => "Germany"}.freeze
      CATEGORIES = {north_american_skaters: "North American Skaters", international_skaters: "International Skaters", north_american_goalies: "North American Goalies", international_goalies: "International Goalies"}.freeze

      def format(pick, ranking:, history:, year:)
        position = pick["positionCode"]
        name = "#{localized(pick["firstName"])} #{localized(pick["lastName"])}"
        source = [pick["amateurClubName"], pick["amateurLeague"].present? ? "(#{pick["amateurLeague"]})" : nil].compact.join(" ")
        history = history.present? ? " #{history}" : ""
        source = source.present? ? " from #{source}" : ""
        first = "📝 With pick No. #{pick["overallPick"] || pick["pickInRound"]}#{history} in Round #{pick["round"]} of the #{year} NHL Draft, the #{localized(pick["teamName"])} selected #{DEMONYMS[pick["countryCode"]] || pick["countryCode"]} #{position} #{name}#{source}."
        [first, details(pick, ranking, position)].join("\n\n")
      end

      def pick_history(value, team_abbrev)
        teams = value.to_s.split("-").reject(&:blank?)
        return "" if teams.empty? || teams == [team_abbrev]
        original = teams.first
        via = teams[1...-1].to_a.reverse
        via.empty? ? "(from #{original})" : "(from #{original}, via #{via.join(", ")})"
      end

      def localized(value)
        value.is_a?(Hash) ? value["default"] || value.values.compact.first : value
      end

      def normalized_name(first, last)
        ActiveSupport::Inflector.transliterate("#{first} #{last}".downcase).squish
      end

      private

      def details(pick, ranking, position)
        return ["Ranking: Unranked", height_line(pick["height"]), weight_line(pick["weight"])].compact.join("\n") unless ranking
        category = CATEGORIES[ranking["category"].to_s.to_sym]
        lines = []
        lines << "Ranking: #{ranking["finalRank"].ordinalize} in #{category}" if ranking["finalRank"] && category
        lines << height_line(ranking["heightInInches"])
        lines << weight_line(ranking["weightInPounds"])
        lines << "#{position == "G" ? "Catches" : "Shoots"}: #{ranking["shootsCatches"]}" if ranking["shootsCatches"]
        lines << "Birthday: #{Date.parse(ranking["birthDate"]).strftime("%m/%d/%Y")}" if ranking["birthDate"]
        lines << "Birthplace: #{birthplace(ranking)}" if birthplace(ranking).present?
        lines.compact.join("\n")
      end

      def height_line(inches)
        inches = inches.to_i
        "Height: #{inches / 12}'#{inches % 12}\"" if inches.positive?
      end

      def weight_line(weight)
        "Weight: #{weight} lbs" if weight
      end

      def birthplace(ranking)
        city = ranking["birthCity"]
        province = ranking["birthStateProvince"]
        country = ranking["birthCountry"]
        return "#{city}, #{province}" if province.present?
        city.present? && country.present? ? "#{city}, #{COUNTRIES[country] || country}" : city
      end
    end
  end
end
