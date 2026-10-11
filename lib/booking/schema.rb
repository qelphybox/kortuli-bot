module Booking
  # Idempotent schema. Small enough that `create_table?` beats a migration
  # directory, with one guarded `alter_table` below for the column that arrived
  # after there was live data. The day there are three of those, this becomes a
  # migration directory.
  module Schema
    def self.apply(db)
      db.create_table?(:clubs) do
        primary_key :id
        String :slug, null: false, unique: true
        String :name, null: false
        String :adapter, null: false
        String :settings, null: false, default: "{}"
        Integer :poll_interval_seconds, null: false, default: DEFAULT_POLL_INTERVAL_SECONDS
        TrueClass :enabled, null: false, default: true
        # How far along the sliding window this club has actually been polled.
        # The differ needs this to tell "new day opened" from "someone cancelled".
        Date :observed_through
        DateTime :created_at, null: false
      end

      # The current snapshot, and only the current snapshot: a row here means
      # the slot is free right now. Taken slots are deleted, not flagged.
      db.create_table?(:slots) do
        primary_key :id
        String :club_slug, null: false
        String :slot_key, null: false, unique: true
        String :court_ref, null: false
        String :court_label, null: false
        DateTime :starts_at, null: false
        DateTime :ends_at, null: false
        String :price
        String :deeplink
        index [:club_slug]
      end

      # Append-only log of transitions. Cheap to keep, and the substrate for
      # "when do evening slots usually free up?" later on.
      db.create_table?(:events) do
        primary_key :id
        String :club_slug, null: false
        String :slot_key, null: false
        String :kind, null: false
        String :court_label
        DateTime :starts_at, null: false
        DateTime :occurred_at, null: false
        index [:occurred_at]
      end

      db.create_table?(:watches) do
        primary_key :id
        Bignum :user_id, null: false
        String :club_slugs, null: false  # JSON array
        String :weekdays, null: false    # JSON array of Time#wday integers
        Integer :from_minute, null: false
        Integer :to_minute, null: false
        TrueClass :active, null: false, default: true
        DateTime :created_at, null: false
        # Set only for a Dated watch, which is a narrowing rather than a second
        # kind of thing: the same record, with its weekdays set to this date's
        # weekday and its hours to a single hour. Null is what makes a watch
        # Standing.
        Date :date
        index [:user_id]
      end

      # The unique index is the whole deduplication strategy. Without it the
      # first flap on a club's site sends forty messages and earns a block.
      db.create_table?(:notifications) do
        primary_key :id
        Integer :watch_id, null: false
        String :slot_key, null: false
        DateTime :sent_at, null: false
        unique %i[watch_id slot_key]
      end

      # The clubs a person has starred. A row per star rather than a JSON column
      # on some user record, because there is no user record — a person is a
      # Telegram id and nothing else — and a unique pair makes starring twice
      # the same as starring once.
      db.create_table?(:favourites) do
        primary_key :id
        Bignum :user_id, null: false
        String :club_slug, null: false
        DateTime :created_at, null: false
        unique %i[user_id club_slug]
      end

      # The last Poll of each club and how it went, overwritten every tick.
      # State rather than history: the log keeps the history.
      db.create_table?(:polls) do
        String :club_slug, primary_key: true
        DateTime :polled_at, null: false
        String :outcome, null: false
        String :summary, null: false
      end

      # `create_table?` does nothing to a table that already exists, and by the
      # time the Dated watch arrived there were watches in the file. Guarded so
      # it is as re-runnable as everything above it.
      db.alter_table(:watches) { add_column :date, Date } unless db[:watches].columns.include?(:date)
    end
  end
end
