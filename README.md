# Rod The Bot

A Bluesky bot to post in-game updates for NHL games

## About This Project

Now that my primary social media home is [Bluesky](https://bsky.app), I wanted to bring in some in-game NHL updates into the timeline. This bot leverages the [NHL StatsWeb API](https://gitlab.com/dword4/nhlapi) to pull live game data, and post updates to Bluesky.

The project leverages my previous work with a Twitter bot to post automated goal calls to Twitter. It was written to power the Bluesky account [canesgameday@bsky.social](https://bsky.app/profile/canesgameday.bsky.social), but should be configurable for accounts following any NHL team.

## Installation

You can install and run raw source code, or use the Docker image.

### Raw source code

1. Clone the repo from GitHub: [minter/rod_the_bot](https://github.com/minter/rod_the_bot)
2. Install dependencies: `bundle install`
3. Create a `.env` file (see below)
4. Run the background job processor: `bundle exec sidekiq`
5. Optional - Run the web UI to monitor Sidekiq: `bin/rails s`
  
## Technical Architecture

Key system components and dependencies:
* Ruby 3+: The language
* Rails 7+: The framework
* Sidekiq 7+: Background job processing
* Redis 7+: State maintenance
* HTTParty: NHL API client

## TODO
* Enable auto-run via Sidekiq Scheduler
* Get docker-compose working for production
* Add additional game events (Time On Ice, period starts, etc)

## Contributing

## Licensing

See LICENSE file for details.
