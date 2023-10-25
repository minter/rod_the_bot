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

## Configuration using .env

Rod The Bot is managed by system environment variables, stored in a file named `.env` in the root of the project. You must create one of these with the appropriate values for your environment. An example file is provided below:

```
NHL_TEAM_ID=12
REDIS_URL=redis://localhost:6379/9
TIME_ZONE=America/New_York
BLUESKY_USERNAME=YOUR_USERNAME.bsky.social
BLUESKY_APP_PASSWORD=YOUR APP PASSWORD
BLUESKY_URL=https://bsky.social
BLUESKY_ENABLED=true
DEBUG_POSTS=false
TEAM_HASHTAGS="#LetsGoCanes #CauseChaos"
WEB_PORT=3000
```

### NHL_TEAM_ID

Every NHL franchise has an ID in the stats system. This is used to identify the team that you want to follow. IDs for all active NHL teams can be found in this table:

| Team Name             | Team ID |
| --------------------- | ------- |
| Anaheim Ducks         | 24      |
| Arizona Coyotes       | 53      |
| Boston Bruins         | 6       |
| Buffalo Sabres        | 7       |
| Calgary Flames        | 20      |
| Carolina Hurricanes   | 12      |
| Chicago Blackhawks    | 16      |
| Colorado Avalanche    | 21      |
| Columbus Blue Jackets | 29      |
| Dallas Stars          | 25      |
| Detroit Red Wings     | 17      |
| Edmonton Oilers       | 22      |
| Florida Panthers      | 13      |
| Los Angeles Kings     | 26      |
| Minnesota Wild        | 30      |
| Montréal Canadiens    | 8       |
| Nashville Predators   | 18      |
| New Jersey Devils     | 1       |
| New York Islanders    | 2       |
| New York Rangers      | 3       |
| Ottawa Senators       | 9       |
| Philadelphia Flyers   | 4       |
| Pittsburgh Penguins   | 5       |
| St. Louis Blues       | 19      |
| San Jose Sharks       | 28      |
| Seattle Kraken        | 55      |
| Tampa Bay Lightning   | 14      |
| Toronto Maple Leafs   | 10      |
| Vancouver Canucks     | 23      |
| Vegas Golden Knights  | 54      |
| Washington Capitals   | 15      |
| Winnipeg Jets         | 52      |

### REDIS_URL

Rod The Bot uses Redis to keep track of plays that it has already seen. This is used to prevent duplicate posts. You can use any Redis instance that you want, but the default is to use a local instance on port 6379, database 9. If you are using the docker-compose method, this will be overridden in the `docker-compose.yml` file.

### TIME_ZONE

The NHL Stats API returns all times in UTC. This setting is used to convert those times to your local time zone. The time zone must be specified in the Rails-style format like `America/New_York`, not `EDT` or other formats. You can find a list of valid time zone names [here](https://api.rubyonrails.org/classes/ActiveSupport/TimeZone.html).

### BLUESKY_USERNAME and BLUESKY_APP_PASSWORD

These are the credentials for the Bluesky account that you want to post to. You can find your app password in the [Bluesky settings](https://bsky.social/settings/apps). Note that when you create an app password, you will only be shown the password once. If you lose it, you will need to create a new one.

### BLUESKY_URL

This is the URL of the Bluesky instance that you want to post to. The default is the main Bluesky instance at https://bsky.social. If you are running your own instance, you can use that URL instead.

### BLUESKY_ENABLED

This setting controls whether Rod The Bot will actually post to Bluesky. If you want to test the bot without posting, set this to `false`.

### DEBUG_POSTS

This setting controls whether Rod The Bot will print the post text to the console. This is useful for testing, but should be set to `false` in production.

### TEAM_HASHTAGS

This setting controls the hashtags that will be added to each post. You can add as many as you want, but they must be separated by spaces. You can use this if your team has official hashtags that you would like to include.

### WEB_PORT

This setting controls the port that the web UI will listen on. This is only used if you are running the web UI.
  
## Technical Architecture

Key system components and dependencies:
* Ruby 3+: The language
* Rails 7+: The framework
* Sidekiq 7+: Background job processing
* Redis 7+: State maintenance
* HTTParty: NHL API client

## TODO
* Get docker-compose working for production

## Contributing

## Licensing

See LICENSE file for details.
