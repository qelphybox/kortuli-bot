module Booking
  module Repo
    # How each Club's last Poll went: one row per club, overwritten every
    # tick. The log says the same thing a line at a time; this is the part of
    # it a dashboard can read without parsing prose — and the honest answer to
    # "is the poll loop still ticking?", which a live process alone is not.
    class Polls
      OUTCOMES = %w[ok suspect failed].freeze

      Poll = Data.define(:club_slug, :polled_at, :outcome, :summary) do
        def ok? = outcome == "ok"
      end

      def initialize(db) = @db = db

      def record(club_slug, outcome:, summary:, at: Clock.now)
        raise ArgumentError, "unknown outcome #{outcome}" unless OUTCOMES.include?(outcome.to_s)

        @db[:polls].insert_conflict(target: :club_slug, update: { polled_at: at, outcome: outcome.to_s, summary: })
                   .insert(club_slug: club_slug.to_s, polled_at: at, outcome: outcome.to_s, summary:)
      end

      def all = @db[:polls].order(:club_slug).to_h { [_1[:club_slug], to_poll(_1)] }

      private

      def to_poll(row) = Poll.new(club_slug: row[:club_slug], polled_at: row[:polled_at], outcome: row[:outcome], summary: row[:summary])
    end
  end
end
