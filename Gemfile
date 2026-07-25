source "https://rubygems.org"

gem "faraday", "~> 2.9"           # HTTP for adapters: timeouts, retries, middleware
gem "faraday-retry", "~> 2.2"     # exponential backoff on 429/5xx, honours Retry-After
gem "rufus-scheduler", "~> 3.9"   # poll scheduling: intervals, jitter, overlap handling
gem "sequel", "~> 5.78"           # lightweight ORM + migrations over SQLite
gem "sqlite3", "~> 2.0"
gem "telegram-bot-ruby", "~> 2.0"
gem "tzinfo", "~> 2.0"            # Asia/Tbilisi <-> UTC at the display boundary

group :development, :test do
  gem "dotenv", "~> 3.1"          # local .env; on the VPS systemd supplies the environment
  gem "rake", "~> 13.2"
  gem "rspec", "~> 3.13"
end
