module Booking
  module Ops
    # Everything the owner's dashboard shows, read at the moment it is asked
    # for: are the three processes alive, did every club's last Poll work, how
    # big is the database, how full is the disk under it. Nothing here is
    # cached or collected in the background — each reading is cheap at this
    # size, and a number that is a minute old is the one you cannot trust
    # during an incident.
    class Dashboard
      PROCESSES = %w[poller bot web].freeze

      Storage = Data.define(:files, :tables) do
        def total_bytes = files.sum { _2 }
      end

      Activity = Data.define(:people, :active_watches, :notified_24h, :freed_24h)

      # A club and how its last Poll went. `state` is the outcome, unless the
      # poll is old enough that the outcome no longer says anything: then it
      # is "stale", and "never" for a club with no poll on record at all.
      ClubPoll = Data.define(:club, :poll, :state)

      # Three missed ticks. A tick walks every club one after another, and a
      # club that times out holds the rest up, so one late tick is not news.
      MISSED_TICKS = 3

      def initialize(db:, database_path:, log_dir:, poll_every: Config.poll_every_seconds)
        @db = db
        @database_path = database_path
        @log_dir = log_dir
        @stale_after = poll_every * MISSED_TICKS
      end

      def processes = PROCESSES.map { Heartbeat.read(@log_dir, _1) }

      def polls(now: Clock.now)
        last = Repo::Polls.new(@db).all

        Repo::Clubs.new(@db).enabled.map do |club|
          poll = last[club.slug]
          state =
            if poll.nil? then "never"
            elsif now - poll.polled_at > @stale_after then "stale"
            else poll.outcome
            end

          ClubPoll.new(club:, poll:, state:)
        end
      end

      # The file and the two SQLite keeps beside it in WAL mode. The WAL can
      # outgrow the database between checkpoints, which is worth seeing.
      def storage
        files = @database_path ? ["", "-wal", "-shm"].filter_map { |suffix| sized("#{@database_path}#{suffix}") } : []
        tables = @db.tables.sort.to_h { [_1.to_s, @db[_1].count] }

        Storage.new(files:, tables:)
      end

      # Measured where the database lives, because that is the disk that
      # fills up.
      def disk = Host.disk(@database_path ? File.dirname(File.expand_path(@database_path)) : @log_dir)

      def load_average = Host.load_average

      def memory = Host.memory

      def activity(now: Clock.now)
        since = now - 86_400
        people = @db[:watches].select(:user_id).union(@db[:favourites].select(:user_id)).count

        Activity.new(
          people:,
          active_watches: @db[:watches].where(active: true).count,
          notified_24h: @db[:notifications].where { sent_at >= since }.count,
          freed_24h: @db[:events].where(kind: "became_available").where { occurred_at >= since }.count
        )
      end

      def logs = LogSearch.new(dir: @log_dir)

      private

      def sized(path) = File.exist?(path) ? [File.basename(path), File.size(path)] : nil
    end
  end
end
