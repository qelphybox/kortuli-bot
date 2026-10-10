require "date"
require "time"

module Booking
  module Adapters
    # Padel Academy runs its own Vue client over a Laravel API, and unlike
    # every other club here it shows its schedule only to a signed-in member.
    # So this adapter holds an account: it logs in with an email and password
    # from the environment, keeps the bearer token it gets back, and asks one
    # court and one date at a time — the same single call the club's own
    # dashboard makes.
    #
    # The answer is a list of *free* starts as bare "HH:MM", which is the
    # contract the differ wants without any inverting. The club books until
    # 02:00 and files 00:00 and 01:00 under the date before, as Kus Tba does;
    # `OpeningHours#starts_by_label` is what puts them on the right day.
    #
    # It never books. `/booking/save` starts a bank payment, and nothing here
    # calls it.
    class Padelacademy
      BASE_URL = "https://booking.padelacademy.ge/api".freeze
      # The club's picker reaches the end of next month, and the server answers
      # past that too. This only caps what we ask; the horizon does the rest.
      DEFAULT_MAX_DAYS = 14
      HOUR = 3600
      HEADERS = { "X-Requested-With" => "XMLHttpRequest", "Accept-Language" => "en" }.freeze

      # The poller builds a fresh adapter every tick, so a token kept on the
      # instance would mean a login every four minutes. Kept per email, for
      # the life of the process.
      def self.tokens = @tokens ||= {}

      def initialize(club, http:, credentials: Config.padel_academy_credentials, clock: Clock, tokens: self.class.tokens)
        @club = club
        @http = http
        @credentials = credentials
        @clock = clock
        @tokens = tokens
        @base_url = club.settings.fetch("base_url", BASE_URL)
        @max_days = Integer(club.settings.fetch("max_days", DEFAULT_MAX_DAYS))
      end

      def fetch(date_range)
        raise SourceUnavailable, "PADEL_ACADEMY_EMAIL and PADEL_ACADEMY_PASSWORD are not set" unless @credentials

        now = @clock.now

        date_range.to_a.first(@max_days)
                  .product(courts)
                  .flat_map { |date, court| court_slots(date, court, now) }
                  .uniq(&:key)
      end

      private

      # Hard-coded in the club's own client as `<option value="1">` to "3";
      # there is no endpoint that lists them.
      def courts = (1..Integer(@club.court_count)).map(&:to_s)

      def court_slots(date, court, now)
        starts = @club.opening_hours.starts_by_label(date)

        free_labels(date, court).filter_map do |label|
          starts_at = starts[label]
          # The server already drops hours that have started; checking again
          # costs nothing and keeps a stale answer out of the snapshot.
          slot(court, starts_at) if starts_at && starts_at > now
        end
      end

      def free_labels(date, court)
        url = "#{@base_url}/booking/check"
        hours = signed_in { |token| @http.post_json(url, { "date" => date.to_s, "court" => court }, headers: auth(token)) }
        # An error body would otherwise read as a court with nothing free.
        raise SourceUnavailable, "#{url}: expected a list of hours, got #{hours.inspect[0, 200]}" unless hours.is_a?(Array)

        hours.map(&:to_s)
      end

      # A token can expire or be revoked from the other side. One fresh login
      # per refusal; a second refusal is an ordinary failure for the tick.
      def signed_in
        yield token
      rescue Unauthorized
        @tokens.delete(@credentials[:email])
        yield token
      end

      def token = @tokens[@credentials[:email]] ||= login

      def login
        url = "#{@base_url}/login"
        payload = @http.post_json(url, { "email" => @credentials[:email], "password" => @credentials[:password] }, headers: HEADERS)
        token = payload["token"] if payload.is_a?(Hash)
        # Says nothing about the payload: it carries the member's profile.
        raise SourceUnavailable, "#{url}: no token in the response" unless token.is_a?(String) && !token.empty?

        token
      end

      def auth(token) = HEADERS.merge("Authorization" => "Bearer #{token}")

      def slot(court, starts_at)
        Slot.new(
          club_slug: @club.slug,
          court_ref: @club.canonical_court(court),
          court_label: "Court #{court}",
          starts_at:,
          ends_at: starts_at + HOUR,
          price: @club.settings["price"],
          # The dashboard sits behind the login; the front door is all there is.
          deeplink: @club.settings["booking_url"]
        )
      end
    end
  end
end
