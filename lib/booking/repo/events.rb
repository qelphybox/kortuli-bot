module Booking
  module Repo
    # Append-only transition log. Nothing reads it in the MVP; it exists so the
    # history is not lost while the snapshot keeps being overwritten.
    class Events
      def initialize(db) = @db = db

      def record(club_slug:, kind:, slots:, at: Clock.now)
        return if slots.empty?

        @db[:events].multi_insert(
          slots.map do |slot|
            {
              club_slug: club_slug.to_s,
              slot_key: slot.key,
              kind: kind.to_s,
              court_label: slot.court_label,
              starts_at: slot.starts_at,
              occurred_at: at
            }
          end
        )
      end

      def count_by_kind = @db[:events].group_and_count(:kind).to_h { [_1[:kind], _1[:count]] }
    end
  end
end
