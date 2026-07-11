module RodTheBot
  module Milestones
    class Formatter
      EMOJI = {"goal" => "🚨", "assist" => "🍎", "point" => "🎯", "win" => "🥅", "shutout" => "🛡️"}.freeze

      def format(player_name, event)
        event.first ? first(player_name, event.type) : achievement(player_name, event.type, event.value)
      end

      private

      def achievement(name, type, value)
        emoji = EMOJI.fetch(type)
        "#{emoji} MILESTONE! #{name} has reached #{value} career #{type.pluralize(value)}! #{emoji}"
      end

      def first(name, type)
        emoji = EMOJI.fetch(type)
        verb = %w[win shutout].include?(type) ? "earned" : "scored"
        "#{emoji} MILESTONE! #{name} has #{verb} their first career NHL #{type}! #{emoji}"
      end
    end
  end
end
