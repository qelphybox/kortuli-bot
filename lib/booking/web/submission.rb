module Booking
  module Web
    # What somebody picked on the create form, narrowed to what was actually on
    # offer, plus whether it describes a watch that could ever fire.
    #
    # A form is a suggestion, not a promise: the page it came from may be old,
    # or may not have been our page at all. So every value is checked against
    # the same lists the screen renders from — asking one place is what keeps
    # the form and the guard from answering differently about what was offered.
    # What the form offers, and therefore what a submission is checked against.
    # Module-level rather than inside the Data.define below, because a constant
    # assigned in that block would land here anyway — Ruby binds it lexically,
    # not to the class — and a constant that is not where it appears to be is a
    # trap for whoever edits this next.
    #
    # Nobody plays at 04:00 and no club is open then, so offering the whole day
    # would be offering nothing. The end runs one hour further: a club open
    # until midnight still sells the 23:00 hour.
    START_HOURS = (6..23).freeze
    LAST_HOUR = 24
    END_HOURS = ((START_HOURS.first + 1)..LAST_HOUR).freeze
    # Monday-first, as a European calendar reads. The numbers themselves are
    # Time#wday, which is what Watch#covers? compares against.
    MONDAY_FIRST = [1, 2, 3, 4, 5, 6, 0].freeze

    Submission = Data.define(:club_slugs, :weekdays, :from_hour, :to_hour) do
      def self.from(params, watched_slugs:)
        new(
          club_slugs: Array(params[:club_slugs]).map(&:to_s) & watched_slugs,
          weekdays: Array(params[:weekdays]).filter_map { Integer(_1.to_s, exception: false) } & MONDAY_FIRST,
          from_hour: offered(params[:from_hour], START_HOURS),
          to_hour: offered(params[:to_hour], END_HOURS)
        )
      end

      def self.offered(value, hours)
        hour = Integer(value.to_s, exception: false)

        hour if hour && hours.cover?(hour)
      end
      private_class_method :offered

      def picked_club?(slug) = club_slugs.include?(slug)

      def picked_day?(day) = weekdays.include?(day)

      # Every reason at once rather than the first: fixing one thing only to be
      # told about the next is what makes a form feel like an interrogation.
      def refusals
        [
          (Messages.pick_at_least_one_club if club_slugs.empty?),
          (Messages.pick_at_least_one_day if weekdays.empty?),
          hour_refusal
        ].compact
      end

      # Hours the screen never offered and an end that is not after its start
      # are different mistakes, and saying "the end must be after the start"
      # about the word "elevenses" would be answering a question nobody asked.
      def hour_refusal
        return Messages.pick_hours_on_offer unless from_hour && to_hour
        return Messages.pick_a_later_end unless to_hour > from_hour

        nil
      end

      # Hours on the way in, minutes on the way out: the form thinks in whole
      # hours because that is how the slots are sold, and the Watch thinks in
      # minutes because that is what its window compares.
      def to_watch = { club_slugs:, weekdays:, from_minute: from_hour * 60, to_minute: to_hour * 60 }
    end
  end
end
