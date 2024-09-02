source "https://rubygems.org"

ruby "3.3.3"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.2.1"

# Use SQLite as the database for Active Record
gem "sqlite3", "~>2"

# Use the Puma web server [https://github.com/puma/puma]
# gem "puma", ">= 5.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[windows jruby]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

gem "bskyrb", "~> 0.5.3"
gem "dotenv-rails", "~> 3", require: "dotenv/load"
gem "httparty", "~> 0"
gem "pry-rails"
gem "redis", "~>5"
gem "sidekiq", "~> 7"
gem "sidekiq-scheduler", "~> 5"

group :test do
  gem "minitest"
  gem "timecop"
  gem "vcr"
  gem "webmock"
end
group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[mri windows]
end

group :development do
  gem "bundler-audit"
  gem "standard"
end
