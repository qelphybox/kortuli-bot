source "https://rubygems.org"

gem "faraday", "~> 2.9"           # HTTP for adapters: timeouts, retries, middleware
gem "rake", "~> 13.2"             # not just for tests: `rake poll` is the diagnostic on a live server
gem "faraday-retry", "~> 2.2"     # exponential backoff on 429/5xx, honours Retry-After
gem "rufus-scheduler", "~> 3.9"   # poll scheduling: intervals, jitter, overlap handling
gem "sequel", "~> 5.78"           # lightweight ORM + migrations over SQLite
gem "sqlite3", "~> 2.0"
gem "telegram-bot-ruby", "~> 2.0"
gem "tzinfo", "~> 2.0"            # Asia/Tbilisi <-> UTC at the display boundary

group :development, :test do
  gem "dotenv", "~> 3.1"          # local .env only; the container gets its environment from Kamal
  gem "kamal", "~> 2.12"          # deploy tool; pinned so it cannot drift, excluded from the image
  gem "rspec", "~> 3.13"
end
