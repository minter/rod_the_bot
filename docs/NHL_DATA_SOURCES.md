# NHL data sources

This document records NHL-hosted data sources that may be useful for future
features but are not yet integrated into Rod The Bot.

## Playing roster report

- URL: [TRPRALL.TXT](https://secure.nhl.com/media/roster/TRPRALL.TXT)
- Format: UTF-8, fixed-width plain text covering every NHL team.
- Contents: season and update timestamps, active rosters, an `Injury Reserve
  List` for each team, the date associated with each IR entry, roster totals,
  average roster measurements and age, and player counts by country.
- Potential use: league-wide injured-reserve status during the season.

The copy inspected on August 24, 2026 still contained 2024-25 rosters and
reported `Last update: 06:30:00 01/16/2025`. Before relying on it, verify its
in-season update cadence and whether the date on an IR row means placement on
IR. Treat its fixed-width layout as an undocumented external contract: a future
integration should fetch it through a focused NHL client, normalize the parsed
records at that boundary, and fail contextually if the report shape changes.
