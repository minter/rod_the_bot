source "https://rubygems.org"

ruby "3.4.2"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.0"

# Use the Puma web server [https://github.com/puma/puma]
# gem "puma", ">= 5.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[windows jruby]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

gem "bskyrb", github: "minter/bskyrb", branch: "main"
# gem "bskyrb", path: "/Users/minter/git/bskyrb"
gem "dotenv-rails", "~> 3", require: "dotenv/load"
gem "httparty", "~> 0"
gem "ostruct"
gem "net-smtp", "~> 0.5.1"
gem "nokogiri"
gem "pry-rails"
gem "redis", "~>5"
gem "sidekiq", "~> 8"
gem "sidekiq-scheduler", "~> 6"
gem "streamio-ffmpeg", ">= 3.0.2"
gem "uri", ">= 1.0.3"

group :test do
  gem "minitest"
  gem "timecop"
  gem "vcr"
  gem "webmock"
  gem "mocha"
  gem "mock_redis"
end
group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[mri windows]
end

group :development do
  gem "bundler-audit"
  gem "standard"
end

gem "watir", "~> 7.3"
