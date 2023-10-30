# Rod The Bot

A Bluesky bot to post in-game updates for NHL games

## About This Project

Now that my primary social media home is [Bluesky](https://bsky.app), I wanted to bring in some in-game NHL updates into the timeline. This bot leverages the [NHL StatsWeb API](https://gitlab.com/dword4/nhlapi) to pull live game data, and post updates to Bluesky.

The project leverages my previous work with a Twitter bot to post automated goal calls to Twitter. It was written to power the Carolina Hurricanes Bluesky account [@canesgameday.bsky.social](https://bsky.app/profile/canesgameday.bsky.social), but should be configurable for accounts following any NHL team.

## Installation

You can install and run raw source code on your server, or use the Docker images (either remotely or by building locally). Remote Docker images are recommended unless you will actively be modifying/developing the software.

### Docker Compose - Remote Images (Easiest)

This method requires you to have [Docker](https://docs.docker.com/get-docker/) and Docker Compose installed, but does not require any of the source code to be located on your system.

1. Create a `.env` file ([see below](#configuration-using-the-env-file)) in the same directory as the `docker-compose.yml` file
2. Download or copy the [`docker-compose-images.yml`](https://github.com/minter/rod_the_bot/blob/main/docker-compose-images.yml) file from the source code, save it to a local file named `docker-compose.yml` in the same directory as the `.env` file
3. Run the software: `docker compose up -d`
4. Check logs by running `docker compose logs -f`
5. Stop the software by running `docker compose down`

### Docker Compose - Local Build (Intermediate)

This method requires you to have [Docker](https://docs.docker.com/get-docker/) and Docker Compose installed, and will build the docker image on your local system.

1. Clone the repo from GitHub: [minter/rod_the_bot](https://github.com/minter/rod_the_bot)
2. Create a `.env` file ([see below](#configuration-using-the-env-file))
3. Run the software: `docker compose up --build -d`
4. Check logs by running `docker compose logs -f`
5. Stop the software by running `docker compose down`

### Raw source code (Hardest)

This method requires you to be running on a system with Ruby 3+ and enough dev tools to build native extensions. You will also need a Redis instance running to store state.

1. Clone the repo from GitHub: [minter/rod_the_bot](https://github.com/minter/rod_the_bot)
2. Install Ruby dependencies: `bundle install`
3. Create a `.env` file ([see below](#configuration-using-the-env-file))
4. Run the background job processor: `bundle exec dotenv sidekiq`
5. Optional - Run the web UI to monitor Sidekiq: `bin/rails s`

## Configuration using the .env file

Rod The Bot is managed by system environment variables, stored in a file named `.env` in the root of the project. You must create one of these with the appropriate values for your environment. An example file is provided below:

```
BLUESKY_APP_PASSWORD=YOUR APP PASSWORD
BLUESKY_ENABLED=true
BLUESKY_URL=https://bsky.social
BLUESKY_USERNAME=YOUR_USERNAME.bsky.social
DEBUG_POSTS=false
NHL_TEAM_ID=12
REDIS_URL=redis://localhost:6379/0
SECRET_KEY_BASE=69782b185cf994696b846e43b8e26a6c9f724905c74bf7556162c5a18cd17edc68a702ffbd0df7e855e2f4c6cf71bf68c794741c9234841f45446c3679bd8e6d 
TEAM_HASHTAGS="#LetsGoCanes #CauseChaos"
TIME_ZONE=America/New_York
WIN_CELEBRATION=Canes Win!
```
You can, in theory, pass the environment variables to the system in other ways, but those methods are not covered here.

### BLUESKY_USERNAME and BLUESKY_APP_PASSWORD

These are the credentials for the Bluesky account that you want to post to. You can create an app password in the [Bluesky settings](https://bsky.social/settings/apps) for the user that you want to post as. The Bluesky username will likely either be in the form of `USER.bsky.social`, or `YOUR-CUSTOM-DOMAIN.COM`, depending on whether you have set up a custom domain for this account.

**Note** that when you create an app password, you will only be shown the password once. If you lose it, you will need to create a new one.

### BLUESKY_ENABLED

This setting controls whether Rod The Bot will actually post to Bluesky. If you want to test the bot without actually posting to the live Bluesky site, set this to `false`.

### BLUESKY_URL

This is the URL of the Bluesky instance that you want to post to. The recommended value is the main Bluesky instance at `https://bsky.social`. If you are running your own instance, you can use that URL instead.

### DEBUG_POSTS

This setting controls whether Rod The Bot will print the post text to the console. This is useful for testing and verifying that posts are being generated, but can be set to `false` in production (unless you need to inspect posts for errors).

### NHL_TEAM_ID

Every NHL franchise has an ID in the stats system. This is used to identify the team that you want to follow, and unlocks happy posts when something good happens to your team. IDs for all active NHL teams can be found in this table:

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

Rod The Bot uses Redis to keep track of plays that it has already seen. This is used to prevent duplicate posts. You can use any Redis instance that you want, but the default is to use a local instance on port 6379, database 0. This Redis instance must be accessible by your local system if you are running in raw source code mode. If you are using the docker compose method, this will be overridden in the `docker-compose.yml` file to point to the Dockerized Redis instance.

### SECRET_KEY_BASE

Rod The Bot is a Ruby on Rails app, and this is needed to run Rails. You can use the example one if you want, but it is recommended that you generate your own. You can do this by generating a 128-character random alphanumeric string and setting it as the value of this variable. To generate a string, you can use a tool like [this online random string generator](https://www.hjkeen.net/htoys/generate.htm).

### TEAM_HASHTAGS

This setting controls the hashtags that will be added to each post. You can add as many as you want, but they must be separated by spaces. You can use this if your team has official hashtags that you would like to include on every post. Leave it blank if you do not want to add them.

### TIME_ZONE

The NHL Stats API returns all times in UTC. This setting is used to convert those times to your local time zone. The time zone must be specified in the Rails-style format like `America/New_York`, not `EDT` or other formats. You can find a list of valid time zone names [here](https://api.rubyonrails.org/classes/ActiveSupport/TimeZone.html).

Common time zones:
* Eastern Time: `America/New_York`
* Central Time: `America/Chicago`
* Mountain Time: `America/Denver`
* Pacific Time: `America/Los_Angeles`
* Arizona Time: `America/Phoenix`

### WIN_CELEBRATION

If this is set, the value provided will be put at the top of your final score post if your team wins! Leave it blank if you do not want this.

## Operation

The scheduler will run at 10am in your time zone every day. It will post some scores/standings information at that time. If there is no game for your team that day, it will then silently exit. 

If there is a game, it will post some team preview information (scoring, goaltending, etc) over the next 90 minutes. It will also enqueue the game feed job to start checking the data feed approximately 15 minutes before the game start time, and will run every 30 seconds until the game is marked as a final. Once the game is final, it will enqueue the post-game jobs (final score, three stars) to run once and quit until tomorrow.

## Technical Architecture

Key system components and dependencies:
* Ruby 3+: The language
* Rails 7+: The framework
* Sidekiq 7+: Background job processing
* Redis 7+: State maintenance
* HTTParty: NHL API client

## TODO
* Fix issues with web UI in Docker

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/minter/rod_the_bot

## Licensing

See LICENSE file for details.
