# Rod The Bot

A Bluesky bot to post in-game updates for NHL games

## About This Project

Now that my primary social media home is [Bluesky](https://bsky.app), I wanted to bring in some in-game NHL updates into the timeline. This bot leverages the new [NHL API](https://github.com/Zmalski/NHL-API-Reference) to pull live game data, and post updates to Bluesky.

The project leverages my previous work with a Twitter bot to post automated goal calls to Twitter. It was written to power the Carolina Hurricanes Bluesky account [@canesgameday.bsky.social](https://bsky.app/profile/canesgameday.bsky.social), but should be configurable for accounts following any NHL team.

## Installation

You can install and run raw source code on your server, or use the Docker images (either remotely or by building locally). Remote Docker images are recommended unless you will actively be modifying/developing the software.

### Docker Compose - Remote Images (Easiest)

This method requires you to have [Docker](https://docs.docker.com/get-docker/) and Docker Compose installed, but does not require any of the source code to be located on your system.

1. Create a `.env` file ([see below](#configuration-using-the-env-file)) in the same directory as the `docker-compose.yml` file
2. Download or copy the [`docker-compose-images.yml`](https://github.com/minter/rod_the_bot/blob/main/docker-compose-images.yml) file from the source code, save it to a local file named `docker-compose.yml` in the same directory as the `.env` file
3. Run the software: `docker compose up --build -d`
4. Stop the software by running `docker compose down`

[Check the logs](#checking-the-logs) to make sure that the software is running correctly.

### Docker Compose - Local Build (Intermediate)

This method requires you to have [Docker](https://docs.docker.com/get-docker/) and Docker Compose installed, and will build the docker image on your local system.

1. Clone the repo from GitHub: [minter/rod_the_bot](https://github.com/minter/rod_the_bot)
2. Change into the `rod_the_bot` directory
3. Create a `.env` file ([see below](#configuration-using-the-env-file)) that will live in the root of the `rod_the_bot` directory
4. Run the software: `docker compose up --build -d`
5. Stop the software by running `docker compose down`

[Check the logs](#checking-the-logs) to make sure that the software is running correctly.

### Raw source code (Hardest)

This method requires you to be running on a system with Ruby 3+ and enough dev tools to build native extensions. You will also need a Redis instance running to store state. This has been tested on both Ubuntu 22.04 and OS X Sonoma, but does require a number of dependencies to be installed.

**You will likely only want to use this method if you are planning on actively changing/contributing to the codebase.**

1. Clone the repo from GitHub: [minter/rod_the_bot](https://github.com/minter/rod_the_bot)
2. Install Ruby dependencies: `bundle install` *(address any errors that pop up until this completes)*
3. Create a `.env` file ([see below](#configuration-using-the-env-file))
4. Run the background job processor: `bundle exec dotenv sidekiq`
5. Stop the software by pressing `Ctrl-C`

Logs should be output to the console where you are running Sidekiq.

## Configuration using the .env file

Rod The Bot is managed by system environment variables, stored in a file named `.env` in the root of the project. You must create one of these with the appropriate values for your environment. An example file is provided below:

```
BLUESKY_APP_PASSWORD=YOUR APP PASSWORD
BLUESKY_ENABLED=true
BLUESKY_URL=https://bsky.social
BLUESKY_USERNAME=YOUR_USERNAME.bsky.social
DEBUG_POSTS=false
NHL_TEAM_ID=12
NHL_TEAM_ABBREVIATION=CAR
REDIS_URL=redis://localhost:6379/0
SECRET_KEY_BASE=69782b185cf994696b846e43b8e26a6c9f724905c74bf7556162c5a18cd17edc68a702ffbd0df7e855e2f4c6cf71bf68c794741c9234841f45446c3679bd8e6d 
TEAM_HASHTAGS="#LetsGoCanes #CauseChaos"
TIME_ZONE=America/New_York
WIN_CELEBRATION=Canes Win!
```
You can, in theory, pass the environment variables to the system in other ways, but those methods are not covered here.

### BLUESKY_USERNAME and BLUESKY_APP_PASSWORD

These are the credentials for the Bluesky account that you want to post to. You can create an app password in the [Bluesky settings](https://bsky.app/settings/app-passwords) for the user that you want to post as. The Bluesky username will likely either be in the form of `USER.bsky.social`, or `YOUR-CUSTOM-DOMAIN.COM`, depending on whether you have set up a custom domain for this account.

**Note** that when you create an app password, you will only be shown the password once. If you lose it, you will need to create a new one.

### BLUESKY_ENABLED

This setting controls whether Rod The Bot will actually post to Bluesky. If you want to test the bot without actually posting to the live Bluesky site, set this to `false`.

### BLUESKY_URL

This is the URL of the Bluesky instance that you want to post to. The recommended value is the main Bluesky instance at `https://bsky.social`. If you are running your own instance, you can use that URL instead.

### DEBUG_POSTS

This setting controls whether Rod The Bot will print the post text to the console. This is useful for testing and verifying that posts are being generated, but can be set to `false` in production (unless you need to inspect posts for errors).

### NHL_TEAM_ID and NHL_TEAM_ABBREVIATION

Every NHL franchise has an ID and official three-letter abbreviation in the stats system. This is used to identify the team that you want to follow, and unlocks happy posts when something good happens to your team. IDs and abbreviations for all active NHL teams can be found in this table:

| Team Name             | Team ID | Abbrev. |
| --------------------- | ------- | ------- |
| Anaheim Ducks         | 24      | ANA     |
| Arizona Coyotes       | 53      | ARI     |
| Boston Bruins         | 6       | BOS     |
| Buffalo Sabres        | 7       | BUF     |
| Calgary Flames        | 20      | CGY     |
| Carolina Hurricanes   | 12      | CAR     |
| Chicago Blackhawks    | 16      | CHI     |
| Colorado Avalanche    | 21      | COL     |
| Columbus Blue Jackets | 29      | CBJ     |
| Dallas Stars          | 25      | DAL     |
| Detroit Red Wings     | 17      | DET     |
| Edmonton Oilers       | 22      | EDM     |
| Florida Panthers      | 13      | FLA     |
| Los Angeles Kings     | 26      | LAK     |
| Minnesota Wild        | 30      | MIN     |
| Montréal Canadiens    | 8       | MTL     |
| Nashville Predators   | 18      | NSH     |
| New Jersey Devils     | 1       | NJD     |
| New York Islanders    | 2       | NYI     |
| New York Rangers      | 3       | NYR     |
| Ottawa Senators       | 9       | OTT     |
| Philadelphia Flyers   | 4       | PHI     |
| Pittsburgh Penguins   | 5       | PIT     |
| St. Louis Blues       | 19      | STL     |
| San Jose Sharks       | 28      | SJS     |
| Seattle Kraken        | 55      | SEA     |
| Tampa Bay Lightning   | 14      | TBL     |
| Toronto Maple Leafs   | 10      | TOR     |
| Vancouver Canucks     | 23      | VAN     |
| Vegas Golden Knights  | 54      | VGK     |
| Washington Capitals   | 15      | WSH     |
| Winnipeg Jets         | 52      | WPG     |

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

### Checking the logs

To check logs from the bot when it's running under Docker, go to the directory with your `docker-compose.yml` file and run `docker compose logs -f sidekiq` (to see the background job processor logs scroll by in real time) or `docker compose logs -f redis` (to see the Redis logs). The first one will be more useful, especially if you have `DEBUG_POSTS` set to `true`. You can stop the logs by pressing `Ctrl-C`.

## Ubuntu Systemd Service

If you are running on Ubuntu or other Systemd-compatible Linux, you can use the following systemd service file to run the bot as a service. This will allow it to start automatically on boot, and will restart it if it crashes. This service uses the [Docker Compose - Remote Images](#docker-compose---remote-images-easiest) method to run the bot.

1. Create a file named `/etc/systemd/system/rod_the_bot.service`, and use the contents of the [`rod_the_bot.service-example`](https://github.com/minter/rod_the_bot/blob/main/rod_the_bot.service-example) file in the root of this repository. You will need to modify the `WorkingDirectory`, `User`, and `Group` values to match your setup. The `WorkingDirectory` must contain the `.env` file and the `docker-compose.yml` file.
2. Run `sudo systemctl daemon-reload` to reload the systemd configuration
3. Run `sudo systemctl enable rod_the_bot` to enable the service
4. Run `sudo systemctl start rod_the_bot` to start the service
5. Run `sudo systemctl status rod_the_bot` to check the status of the service
6. Run `sudo systemctl stop rod_the_bot` to stop the service
7. Run `sudo systemctl disable rod_the_bot` to disable the service

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
