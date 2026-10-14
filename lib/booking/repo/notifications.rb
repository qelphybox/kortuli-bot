module Booking
  module Repo
    # Deduplication lives in the unique index, not in application logic. Claiming
    # by insert-and-rescue is race-free by construction; a check-then-send would
    # not be, and the failure mode is spamming a user until they block the bot.
    class Notifications
      def initialize(db) = @db = db

      # True when this caller won the right to send; false when it was already sent.
      def claim(watch_id:, slot_key:, at: Clock.now)
        @db[:notifications].insert(watch_id:, slot_key:, sent_at: at)
        true
      rescue Sequel::UniqueConstraintViolation
        false
      end

      def sent?(watch_id:, slot_key:) = !@db[:notifications].where(watch_id:, slot_key:).empty?

      # What these watches were told about since `since`, newest first: the
      # slots the home screen may still have a banner for.
      def sent_since(watch_ids, since:)
        return [] if watch_ids.empty?

        @db[:notifications].where(watch_id: watch_ids).where { sent_at >= since }.reverse(:sent_at).all
      end

      # A send that failed should not keep the slot muted forever.
      def release(watch_id:, slot_key:) = @db[:notifications].where(watch_id:, slot_key:).delete
    end
  end
end
