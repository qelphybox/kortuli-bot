module Booking
  # One date's free Cells, narrowed to a span of hours if asked, in the shape a
  # message forwarded to the people you play with needs: per Club, the stretches
  # of consecutive free hours and one link to book them.
  #
  # Pure, like the Grid it reads from. It decides what goes in; Messages decides
  # how it reads.
  module Rundown
    HOUR = 3600

    # Consecutive free hours at one Club, as one stretch: "18:00–21:00" says the
    # same as three separate hours and is a third as long to read in a chat.
    Run = Data.define(:starts_at, :ends_at)

    Entry = Data.define(:club_name, :price, :runs, :link)

    # `window` is nil for the whole day, or the Range of instants it was
    # narrowed to. `booked` names the clubs with nothing free in it, so the
    # reader knows they were looked at rather than forgotten.
    Sheet = Data.define(:date, :window, :entries, :booked) do
      def empty? = entries.empty?
    end

    def self.build(table:, clubs:, window: nil, now: Clock.now)
      prices = clubs.to_h { [_1.slug, _1.settings["price"]] }
      entries = []
      booked = []

      table.rows.each do |row|
        # An hour that has begun cannot be played however free it is, so a
        # message that offered it would send somebody across town for nothing.
        free = row.cells.select { _1.free? && _1.starts_at > now && (window.nil? || window.cover?(_1.starts_at)) }
        next booked << row.club_name if free.empty?

        entries << Entry.new(club_name: row.club_name, price: prices[row.club_slug], runs: runs(free), link: free.first.deeplink)
      end

      Sheet.new(date: table.date, window:, entries:, booked:)
    end

    def self.runs(cells)
      cells.slice_when { |a, b| b.starts_at - a.starts_at > HOUR }.map do |stretch|
        Run.new(starts_at: stretch.first.starts_at, ends_at: stretch.last.starts_at + HOUR)
      end
    end
    private_class_method :runs
  end
end
