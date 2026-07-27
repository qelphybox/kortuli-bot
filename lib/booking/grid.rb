module Booking
  # Turns the current free-Slot snapshot into what the mini app draws: one row
  # per Club, one Cell per hour of that Club's day.
  #
  # Pure, and deliberately so — it is the piece with all the interesting cases
  # in it (a club open past midnight, a court-level club against an hour-level
  # one, an hour nobody can book) and none of them need a database or a
  # network to exercise.
  module Grid
    # One hour at one Club on one date, across all of that Club's courts. Free
    # while *any* court is; `free_courts` and `total_courts` are filled in only
    # for a Club whose source names its courts, because inventing a count for
    # the others would be claiming precision the club refused to give.
    Cell = Data.define(:starts_at, :free, :free_courts, :total_courts, :deeplink) do
      def free? = free

      # Whether this Cell can show "2 of 4" rather than merely "something".
      def counted? = !total_courts.nil?

      def local_starts_at = Clock.to_local(starts_at)
    end

    Row = Data.define(:club_slug, :club_name, :cells) do
      # Clubs keep different hours, so a shared column can fall outside this
      # club's day. Nil means "shut", which the screen draws as a gap rather
      # than as something taken.
      def cell_at(starts_at) = cells.find { _1.starts_at == starts_at }
    end

    # One screen: the rows, plus the column axis they share. The axis is the
    # union of every club's hours, because a club open until 02:00 has to be
    # drawable next to one that shut at midnight without either row lying.
    Table = Data.define(:date, :columns, :rows)

    def self.build(clubs:, slots:, date:)
      free = slots.group_by { [_1.club_slug, _1.starts_at] }

      rows = clubs.map do |club|
        cells = club.opening_hours.starts_on(date).map { cell(club, _1, free[[club.slug, _1]] || []) }

        Row.new(club_slug: club.slug, club_name: club.name, cells:)
      end

      Table.new(date:, columns: rows.flat_map(&:cells).map(&:starts_at).uniq.sort, rows:)
    end

    def self.cell(club, starts_at, free_slots)
      Cell.new(
        starts_at:,
        free: free_slots.any?,
        free_courts: (free_slots.map(&:court_ref).uniq.size if club.court_level?),
        total_courts: (club.court_count if club.court_level?),
        # A free hour links where its own Slots point; a taken one still needs
        # somewhere to send a person who taps it out of curiosity.
        deeplink: free_slots.first&.deeplink || club.settings["booking_url"]
      )
    end
    private_class_method :cell
  end
end
