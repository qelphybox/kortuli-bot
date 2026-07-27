module Booking
  module Repo
    # Holds the current free-slot snapshot per club — the differ's other half.
    # Persisted rather than kept in memory so that a restart does not look like
    # "the entire club just opened up".
    class Slots
      def initialize(db) = @db = db

      def snapshot(club_slug)
        @db[:slots].where(club_slug: club_slug.to_s).order(:starts_at, :court_ref).map { to_slot(_1) }
      end

      # Every club at once, for the Grid. The whole snapshot is a few hundred
      # rows across four clubs, so narrowing it to one screen's dates would buy
      # nothing but a chance to get the boundary wrong.
      def all = @db[:slots].order(:club_slug, :starts_at, :court_ref).map { to_slot(_1) }

      # The snapshot is replaced wholesale: the adapter's answer is the truth,
      # and reconciling row-by-row buys nothing at this size.
      def replace(club_slug, slots)
        @db.transaction do
          @db[:slots].where(club_slug: club_slug.to_s).delete
          @db[:slots].multi_insert(slots.map { to_row(_1) }) if slots.any?
        end
      end

      def to_slot(row)
        Slot.new(
          club_slug: row[:club_slug],
          court_ref: row[:court_ref],
          court_label: row[:court_label],
          starts_at: row[:starts_at],
          ends_at: row[:ends_at],
          price: row[:price],
          deeplink: row[:deeplink]
        )
      end

      def to_row(slot)
        {
          club_slug: slot.club_slug,
          slot_key: slot.key,
          court_ref: slot.court_ref,
          court_label: slot.court_label,
          starts_at: slot.starts_at,
          ends_at: slot.ends_at,
          price: slot.price&.to_s,
          deeplink: slot.deeplink
        }
      end
      private :to_slot, :to_row
    end
  end
end
