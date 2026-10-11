module Booking
  module Web
    # The hours the Share screen narrows a Rundown to, as picked from its two
    # lists — and, through `pick`, the hours a Game takes.
    #
    # Hours are counted from the date's own midnight rather than read off the
    # clock, so a club open until 02:00 offers 24 and 25 after 23 instead of
    # wrapping back to 0 — "18:00 to 01:00" has to be a span that comes out
    # forwards. The lists are the Grid's own columns, so the pickers never
    # offer an hour no club sells.
    #
    # A filter rather than a form: anything that is not on offer, or a start
    # that is not before its end, falls back to the whole day instead of being
    # refused. There is nothing to protect, and a page that answers is better
    # than one that explains.
    HourSpan = Data.define(:date, :hours, :from, :to) do
      def self.from(params, date:, columns:)
        hours = columns.map { offset(date, _1) }
        return new(date:, hours:, from: nil, to: nil) if hours.empty?

        from = offered(params[:from], hours)
        to = offered(params[:to], hours.map { _1 + 1 })
        from, to = hours.first, hours.last + 1 unless from && to && from < to

        new(date:, hours:, from:, to:)
      end

      # The hours one Game takes: ticked on a club's hours, or picked from the
      # Game screen's two lists. Unlike `from`, nothing falls back — a span
      # that is not on offer is no game at all, and nil says so.
      #
      # A Game is one stretch, so ticking 19:00 and 21:00 takes the hour
      # between as well. The screen it lands on shows the stretch before
      # anything leaves, with both ends there to correct.
      def self.pick(params, date:, columns:)
        hours = columns.map { offset(date, _1) }
        ticked = Array(params[:hours]).filter_map { Integer(_1.to_s, exception: false) }
        from, to = ticked.any? ? [ticked.min, ticked.max + 1] : [params[:from], params[:to]]
        from = offered(from, hours)
        to = offered(to, hours.map { _1 + 1 })

        new(date:, hours:, from:, to:) if from && to && from < to
      end

      # The hour `at` starts in, counted from the date's own midnight.
      def self.offset(date, at)
        local = Clock.to_local(at)

        ((local.to_date - date).to_i * 24) + local.hour
      end

      def self.offered(value, hours)
        hour = Integer(value.to_s, exception: false)

        hour if hours.include?(hour)
      end
      private_class_method :offered

      def from_choices = hours

      def to_choices = hours.map { _1 + 1 }

      def whole_day? = from.nil? || (from == hours.first && to == hours.last + 1)

      # Nil for the whole day, so the Rundown's heading only names a span
      # somebody actually picked.
      def window = whole_day? ? nil : starts_at...ends_at

      def starts_at = at(from)

      def ends_at = at(to)

      def label(hour) = format("%02d:00", hour % 24)

      private

      def at(hour) = Clock.local_to_utc(format("%s %02d:00", date + (hour / 24), hour % 24))
    end
  end
end
