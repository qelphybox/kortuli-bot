require "time"

module Booking
  module Web
    # One taken Cell, tapped. What it becomes is a narrowing of the Watch that
    # already exists rather than a second kind of thing: this date's weekday,
    # this single hour, and the date attached.
    #
    # Built here rather than in the route for the reason Submission is — the
    # route decides who is asking, and this decides what they asked for. It
    # also means the grid and the route agree about which hours are worth
    # offering, because both ask `askable?` rather than each keeping its own
    # opinion.
    TappedHour = Data.define(:club_slug, :starts_at) do
      def self.from(params, watched_slugs:, horizon:, now: Clock.now)
        at = Time.iso8601(params[:starts_at].to_s).getutc
        slug = params[:club_slug].to_s
        return nil unless watched_slugs.include?(slug) && askable?(at, horizon:, now:)

        new(club_slug: slug, starts_at: at)
      rescue ArgumentError
        nil
      end

      # Worth asking about only if somebody has polled it and it has not
      # already started: an hour outside the horizon is one we never look at,
      # and an hour that has begun cannot be played however free it becomes —
      # the Matcher discards those slots, so such a watch is born expired.
      #
      # The grid draws no button where this is false, rather than drawing one
      # that would be refused.
      def self.askable?(at, horizon:, now: Clock.now)
        at > now && horizon.include?(Clock.local_date(at))
      end

      # Local, because the date a person means is the one on their own clock —
      # an hour after midnight belongs to the day it starts on, which is not
      # the page it was drawn under.
      def local = Clock.to_local(starts_at)

      def date = local.to_date

      def from_minute = (local.hour * 60) + local.min

      # A Cell is an hour and a Slot is an hour, so the window is that hour and
      # nothing either side of it. The last hour of the day ends at 24:00,
      # which is why this is counted in minutes rather than formatted.
      def to_watch
        { club_slugs: [club_slug], weekdays: [local.wday], from_minute:, to_minute: from_minute + 60, date: }
      end

      # The identity of a Dated watch: one club, one date, one hour. Tapping
      # the same Cell twice is the same request, not a second one.
      def asked_by?(watch)
        watch.dated? && watch.date == date && watch.from_minute == from_minute &&
          watch.club_slugs.include?(club_slug)
      end
    end
  end
end
