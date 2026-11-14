module RodTheBot
  module Milestones
    class FranchiseRankFormatter
      def format(player_name, event)
        list = "the franchise's all-time #{event.stat} list"
        rank = event.rank.ordinalize
        subject = "📈 #{player_name} (#{event.total})"

        if event.tied.any?
          "#{subject} ties #{event.tied.to_sentence} for #{rank} on #{list}."
        else
          next_up = " Next up: #{event.next_up.name} (#{event.next_up.total})." if event.next_up
          "#{subject} passes #{event.passed.to_sentence} for sole possession of #{rank} on #{list}.#{next_up}"
        end
      end
    end
  end
end
