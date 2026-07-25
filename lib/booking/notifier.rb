module Booking
  # Turns candidates into messages, exactly once each.
  class Notifier
    def initialize(notifications:, transport:, clubs: {}, logger: nil)
      @notifications = notifications
      @transport = transport
      @clubs = clubs
      @logger = logger
    end

    # Returns the number of messages actually sent.
    def deliver(candidates)
      candidates.count { send_once(_1) }
    end

    private

    def send_once(candidate)
      watch_id = candidate.watch.id
      slot_key = candidate.slot.key

      # Claiming before sending — rather than checking, sending, then recording —
      # means a crash mid-send costs one missed message instead of a loop of
      # duplicates.
      return false unless @notifications.claim(watch_id:, slot_key:)

      begin
        @transport.send_message(
          chat_id: candidate.watch.user_id,
          text: Messages.slot_freed(candidate.slot, club_name(candidate.slot.club_slug))
        )
        true
      rescue StandardError => e
        # A refusal now should not mute this slot for good: hand the claim back
        # so a later tick can try again.
        @notifications.release(watch_id:, slot_key:)
        @logger&.call("notify failed user=#{candidate.watch.user_id} #{e.class}: #{e.message}")
        false
      end
    end

    def club_name(slug) = @clubs.fetch(slug, slug)
  end
end
