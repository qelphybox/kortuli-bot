module Booking
  # Turns candidates into messages, exactly once each.
  class Notifier
    # `forecast` is the Forecast repository, read once per batch so every
    # message in it says the same thing about the same hour. Optional: without
    # one, messages simply carry no weather.
    def initialize(notifications:, transport:, clubs: {}, forecast: nil, logger: nil)
      @notifications = notifications
      @transport = transport
      @clubs = clubs
      @forecast = forecast
      @logger = logger
    end

    # Returns the number of messages actually sent.
    def deliver(candidates)
      return 0 if candidates.empty?

      weather = forecast_by_hour
      candidates.count { send_once(_1, weather) }
    end

    private

    # The weather is a courtesy; the message is the job. A Forecast that
    # cannot be read sends the message without it rather than not at all.
    def forecast_by_hour
      @forecast ? Weather.by_hour(@forecast.hours) : {}
    rescue StandardError => e
      @logger&.call("notify: forecast unreadable — #{e.class}: #{e.message}")
      {}
    end

    def send_once(candidate, weather)
      watch_id = candidate.watch.id
      slot_key = candidate.slot.key

      # Claiming before sending — rather than checking, sending, then recording —
      # means a crash mid-send costs one missed message instead of a loop of
      # duplicates.
      return false unless @notifications.claim(watch_id:, slot_key:)

      begin
        @transport.send_message(
          chat_id: candidate.watch.user_id,
          text: Messages.slot_freed(
            candidate.slot, club_name(candidate.slot.club_slug),
            weather: Weather.worst(weather, candidate.slot.starts_at, candidate.slot.ends_at)
          )
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
