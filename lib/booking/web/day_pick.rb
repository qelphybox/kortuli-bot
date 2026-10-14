require "set"

module Booking
  module Web
    # One date's clubs against the hours somebody wants to play. The answer
    # is binary: a club is on the list when every hour picked is free there,
    # and folded away with a word on what it does have when it is not —
    # "free 18:00 but not 19:00" is not a court for a two-hour game.
    #
    # Nothing picked is "any time": every club with an hour left, by how many.
    # It is where a date opens — the hours are this person's to pick, not
    # ours to guess.
    #
    # Hours are counted from the date's midnight, as HourSpan counts them, so
    # a club open past midnight offers 24 and 25 after 23. Only hours still to
    # come are offered at all: an hour that has started is no use to anybody
    # looking for a court.
    #
    # Pure, like the Grid: the clubs arrive already read, so the rules — the
    # order, the folding, which roof the hint offers — are exercised without a
    # database.
    class DayPick
      # How many of a club's free hours its card has room for, any time.
      CHIPS = 6

      # What the pick needs to know about one club on the date. `free` is the
      # set of hours on offer that it has free; `favourite` is where it stands
      # among this person's stars, nil when it has none. `roofed` is a roof
      # over some court; `open_air` every court in the open — a club without
      # a Profile is neither, because either is a claim. `cover` is the word
      # the hint calls it by: the best shelter it has, nil without a Profile.
      Club = Data.define(:slug, :name, :free, :favourite, :roofed, :open_air, :no_data, :cover) do
        def favourite? = !favourite.nil?
      end

      # A club folded away, and why: `:no_data`, `:only` the hours it has,
      # `:next` or `:last` free hour either side of the span, or `:nothing`.
      Miss = Data.define(:club, :why, :hours)

      # The line over the list when it rains: a club with a roof to book — or
      # no club, when no roof fits, and the line only says when it may rain.
      Hint = Data.define(:club)

      attr_reader :hours, :wanted, :rainy_hours

      # The hours a link asked for, as offered on this date. Nothing asked
      # for is any time, and so is an hour not on offer once it is dropped —
      # as is the "any" older links carry.
      def self.wanted(raw, offered) = offered & raw.to_s.split(",").filter_map { Integer(_1, exception: false) }

      def initialize(hours:, wanted:, rainy:, clubs:)
        @hours = hours
        @wanted = wanted
        @rainy_hours = rainy.to_set
        @clubs = clubs
      end

      def any_time? = wanted.empty?

      # The hours the list answers for: those picked, or the whole day left.
      def span = any_time? ? hours : wanted

      # One unbroken stretch, which is what "18:00–20:00" can say.
      def contiguous? = span.empty? || span.last - span.first + 1 == span.size

      def from = span.first

      def to = span.last && span.last + 1

      # Rain over the hours picked: what puts the roofs first and brings up
      # the hint.
      def rainy? = span.any? { rainy_hours.include?(_1) }

      # Rain anywhere in what is left of the day, for the strip's legend.
      def any_rain? = hours.any? { rainy_hours.include?(_1) }

      def rainy_hour?(hour) = rainy_hours.include?(hour)

      # The rain over the hours picked as stretches, [first, last + 1] each.
      def rain_runs
        span.select { rainy_hour?(_1) }.chunk_while { |a, b| b == a + 1 }.map { [_1.first, _1.last + 1] }
      end

      # The hour strip's links: what tapping an hour leaves picked, nil when
      # that is nothing — any time, the bare date.
      def toggled(hour)
        now = wanted.include?(hour) ? wanted - [hour] : (wanted + [hour]).sort

        now.join(",") unless now.empty?
      end

      # The pick as a link carries it: nil for any time, so a first look
      # stays a bare URL.
      def param = (wanted.join(",") unless any_time?)

      # Favourites first, in the order they were starred; then, when the
      # hours picked are wet, the clubs with a roof; then the rest by name.
      # Distance plays no part — nobody told us where they are.
      def sorted
        @sorted ||= @clubs.sort_by do |club|
          [club.favourite? ? 0 : 1, club.favourite.to_i, rainy? && !club.roofed ? 1 : 0, club.name.downcase]
        end
      end

      def free_in(club) = span.select { club.free.include?(_1) }

      def whole?(club) = !any_time? && free_in(club).size == span.size

      def live?(club) = any_time? ? club.free.any? : whole?(club)

      # On the list: every hour picked free, or anything free at all.
      def live = @live ||= sorted.select { live?(_1) }

      def folded = @folded ||= sorted.reject { live?(_1) }.map { miss(_1) }

      # The free hours a club's card names, any time: the first few.
      def chips(club) = free_in(club).first(CHIPS)

      def more(club) = [free_in(club).size - CHIPS, 0].max

      # The hours picked that rain falls on at this club — only one known to
      # be in the open: a club we know nothing about is not said to be wet.
      def wet_hours(club) = club.open_air ? span.select { rainy_hour?(_1) } : []

      # Rain over the hours picked, and somewhere under a roof to play
      # through it: the first club on the list with a roof and a free hour
      # in the rain — a favourite before anybody else. With no roof to offer
      # it is the rain alone; on a dry span, nothing.
      def hint
        return @hint if defined?(@hint)

        @hint = if rainy?
                  Hint.new(club: live.select(&:roofed).find { sheltered(_1).any? })
                end
      end

      private

      # The free hours at a club that the rain falls on.
      def sheltered(club) = free_in(club).select { rainy_hour?(_1) }

      def miss(club)
        return Miss.new(club:, why: :no_data, hours: []) if club.no_data && club.free.empty?

        some = free_in(club)
        return Miss.new(club:, why: :only, hours: some) if some.any?

        after = hours.find { _1 >= to.to_i && club.free.include?(_1) }
        return Miss.new(club:, why: :next, hours: [after]) if after && !any_time?

        before = hours.reverse.find { _1 < from.to_i && club.free.include?(_1) }
        return Miss.new(club:, why: :last, hours: [before]) if before && !any_time?

        Miss.new(club:, why: :nothing, hours: [])
      end
    end
  end
end
