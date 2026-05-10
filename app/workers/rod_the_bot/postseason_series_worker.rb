module RodTheBot
  class PostseasonSeriesWorker
    include Sidekiq::Worker

    def perform
      carousel = NhlApi.fetch_postseason_carousel
      return if carousel.blank?

      rounds = carousel["rounds"]
      return if rounds.blank?

      current_series = fetch_current_series(rounds)
      return if current_series.blank?

      seed_labels = NhlApi.playoff_seed_labels
      post = format_series(current_series, seed_labels)
      RodTheBot::Post.perform_async(post)
    end

    private

    # Prefer the earliest round that still has an undecided series, so we keep posting that
    # round until every series has a winner—even if the API's currentRound advances early.
    def fetch_current_series(rounds)
      sorted = rounds.sort_by { |r| r["roundNumber"].to_i }
      incomplete = sorted.find { |round| round_in_progress?(round) }
      incomplete || sorted.last
    end

    def round_in_progress?(round)
      round_series(round).any? { |series| !series_decided?(series) }
    end

    def series_decided?(series)
      needed = series["neededToWin"]
      series["topSeed"]["wins"] == needed || series["bottomSeed"]["wins"] == needed
    end

    # The NHL carousel leaks the next round's slot into the current round once a team
    # advances (e.g. the conference-finals "M" series appearing in round 2 with CAR
    # already seeded). Each series carries its own seriesLabel, so keep only the ones
    # that actually belong to this round.
    def round_series(round)
      label = round["roundLabel"]
      (round["series"] || []).select { |series| series["seriesLabel"] == label }
    end

    def format_series(current_series, seed_labels = {})
      post = "📋 Here are the playoff matchups for the #{current_series["roundLabel"].tr("-", " ").titlecase}:\n\n"
      round_series(current_series).each do |series|
        top_seed_won = series["topSeed"]["wins"] == series["neededToWin"]
        bottom_seed_won = series["bottomSeed"]["wins"] == series["neededToWin"]

        trophy_prefix = ""
        trophy_suffix = ""

        if top_seed_won
          trophy_prefix = "🏆 "
        elsif bottom_seed_won
          trophy_suffix = " 🏆"
        end

        top_abbrev = series["topSeed"]["abbrev"]
        bottom_abbrev = series["bottomSeed"]["abbrev"]
        top_label = seed_labels[top_abbrev] ? "(#{seed_labels[top_abbrev]}) " : ""
        bottom_label = seed_labels[bottom_abbrev] ? "(#{seed_labels[bottom_abbrev]}) " : ""

        post += "#{trophy_prefix}#{top_label}#{top_abbrev} #{series["topSeed"]["wins"]} - #{bottom_label}#{bottom_abbrev} #{series["bottomSeed"]["wins"]}#{trophy_suffix}\n\n"
      end
      post
    end
  end
end
