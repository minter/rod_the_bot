module RodTheBot
  module Penalty
    class PostBuilder
      include PeriodFormatter

      SEVERITY = {"MIN" => "Minor", "MAJ" => "Major", "MIS" => "Misconduct", "GMIS" => "Game Misconduct", "MATCH" => "Match", "BEN" => "Minor", "PS" => "Penalty Shot"}.freeze
      NAMES = {
        "delaying-game" => "Delay Of Game", "too-many-men-on-the-ice" => "Too Many Men", "cross-checking" => "Cross-Checking",
        "high-sticking" => "High-Sticking", "high-sticking-double-minor" => "High-Sticking (Double Minor)",
        "checking-from-behind" => "Checking from Behind", "abuse-of-officials" => "Abuse of Officials",
        "unsportsmanlike-conduct" => "Unsportsmanlike Conduct", "unsportsmanlike-conduct-bench" => "Unsportsmanlike Conduct (Bench)",
        "goalie-leave-crease" => "Goaltender Left Crease", "goalie-participation-beyond-center" => "Goaltender Beyond Center Line",
        "illegal-check-to-head" => "Illegal Check to the Head", "playing-without-a-helmet" => "Playing Without a Helmet",
        "throwing-equipment" => "Throwing Equipment", "delaying-game-puck-over-glass" => "Delay of Game - Puck over Glass",
        "delaying-game-face-off-violation" => "Delay of Game - Face-off Violation", "delaying-game-bench-face-off-violation" => "Delay of Game - Bench Face-off Violation",
        "delaying-game-equipment" => "Delay of Game - Equipment", "delaying-game-smothering-puck" => "Delay of Game - Smothering Puck",
        "delaying-game-unsuccessful-challenge" => "Delay of Game - Unsuccessful Challenge", "delaying-game-bench" => "Delay of Game (Bench)",
        "covering-puck-in-crease" => "Covering Puck in Crease", "goalkeeper-displaced-net" => "Goalkeeper Displaced Net",
        "holding-on-breakaway" => "Holding on Breakaway", "hooking-on-breakaway" => "Hooking on Breakaway", "net-displaced" => "Net Displaced",
        "slash-on-breakaway" => "Slashing on Breakaway", "throwing-object-at-puck" => "Throwing Object at Puck", "tripping-on-breakaway" => "Tripping on Breakaway",
        "roughing-removing-opponents-helmet" => "Roughing - Removing Opponent's Helmet", "spearing-double-minor" => "Spearing (Double Minor)",
        "interference-goalkeeper" => "Goaltender Interference", "interference-bench" => "Interference (Bench)", "holding-the-stick" => "Holding the Stick",
        "puck-thrown-forward-goalkeeper" => "Puck Thrown Forward by Goalkeeper", "instigator-misconduct" => "Instigator Misconduct",
        "game-misconduct-head-coach" => "Game Misconduct (Head Coach)"
      }.freeze

      def build(play:, players:, your_team:, their_team:, tracked_team_id:)
        details = play.fetch("details")
        committed = details["committedByPlayerId"]
        served = details["servedByPlayerId"]
        main = players.fetch(committed || served)
        return unless main
        post = (main.team_id == tracked_team_id) ? "🙃 #{your_team.dig("commonName", "default")} Penalty\n\n" : "😵‍💫 #{their_team.dig("commonName", "default")} Penalty!\n\n"
        period = format_period_name(play.dig("periodDescriptor", "number"))
        post + case details["typeCode"]
        when "BEN"
          "Bench Minor - #{penalty_name(details["descKey"])}\nPenalty is served by #{players.name_with_number(served)}\n\nThat's a #{details["duration"]} minute penalty at #{play["timeInPeriod"]} of the #{period}\n"
        when "PS"
          "#{players.name_with_number(committed)} - #{penalty_name(details["descKey"].sub(/^ps-/, ""))}\n\nThat's a penalty shot awarded at #{play["timeInPeriod"]} of the #{period}\n"
        else
          text = "#{players.name_with_number(committed)} - #{penalty_name(details["descKey"])}\n\nThat's a #{details["duration"]} minute #{SEVERITY[details["typeCode"]]} penalty at #{play["timeInPeriod"]} of the #{period}\n"
          text += "\n(Penalty served by #{players.name_with_number(served)})" if served && served != committed
          text
        end
      end

      def penalty_name(key) = NAMES[key] || key.tr("-", " ").titlecase
    end
  end
end
