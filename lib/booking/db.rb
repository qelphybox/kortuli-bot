require "fileutils"
require "sequel"

module Booking
  module DB
    module_function

    def connect(url = Config.database_url)
      # Set before connecting: it decides how Sequel reads timestamps back out.
      Sequel.default_timezone = :utc
      Sequel.application_timezone = :utc

      ensure_directory(url)
      db = Sequel.connect(url)
      # WAL lets the Telegram thread read while the poll thread writes.
      db.run("PRAGMA journal_mode=WAL")
      db.run("PRAGMA foreign_keys=ON")
      db.run("PRAGMA busy_timeout=5000")
      Schema.apply(db)
      db
    end

    def connection = @connection ||= connect

    # The file behind a sqlite:// URL, or nil for an in-memory database.
    def path(url = Config.database_url)
      url[%r{\Asqlite://(?!/)(.+)\z}, 1] || url[%r{\Asqlite://(/.+)\z}, 1]
    end

    def ensure_directory(url)
      path = path(url)
      FileUtils.mkdir_p(File.dirname(path)) if path
    end
  end
end
