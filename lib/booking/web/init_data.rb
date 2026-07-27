require "json"
require "openssl"
require "uri"

module Booking
  module Web
    # Telegram hands a Mini App a signed blob describing who opened it. The
    # signature is an HMAC keyed on the bot token, so verifying it here is what
    # turns "someone loaded our URL" into "this is user 42, and Telegram says
    # so".
    #
    # Note that Telegram delivers this in the URL *fragment*, which browsers
    # never send upstream — the server only ever sees it because the page posts
    # it back. That is why this is a one-time exchange rather than something
    # checked on every request.
    module InitData
      # Telegram issues initData once when the app opens and never refreshes
      # it, so age is the only defence against a captured payload being
      # replayed. A day is long enough that a normal session never trips it.
      MAX_AGE_SECONDS = 86_400
      # Fixed by Telegram: the key under which the bot token is hashed to reach
      # the key that actually signs the payload.
      DERIVATION_KEY = "WebAppData".freeze
      DIGEST = "SHA256".freeze

      # Returns the Telegram user id, or nil for anything that is not a live,
      # correctly signed payload. Telegram sends a display name too, but the
      # server never renders one — the app draws it client-side from the same
      # SDK — so carrying it further would be verified data nobody reads.
      def self.verify(init_data, token:, now: Clock.now)
        fields = parse(init_data) or return nil
        signature = fields.delete("hash") or return nil
        return nil unless fresh?(fields["auth_date"], now)
        return nil unless signed?(fields, signature, token)

        user_id(fields["user"])
      end

      def self.parse(init_data)
        return nil if init_data.nil? || init_data.to_s.empty?

        # Rescue only what malformed input actually raises. A broader rescue
        # here once turned a missing stdlib method into a silent "unsigned",
        # which is the worst possible way for an auth check to fail.
        URI.decode_www_form(init_data.to_s).to_h
      rescue ArgumentError
        nil
      end
      private_class_method :parse

      def self.fresh?(auth_date, now)
        return false if auth_date.nil?

        age = now.to_i - auth_date.to_i
        age >= 0 && age <= MAX_AGE_SECONDS
      end
      private_class_method :fresh?

      def self.signed?(fields, signature, token)
        check_string = fields.keys.sort.map { "#{_1}=#{fields[_1]}" }.join("\n")
        key = OpenSSL::HMAC.digest(DIGEST, DERIVATION_KEY, token.to_s)
        expected = OpenSSL::HMAC.hexdigest(DIGEST, key, check_string)

        # Constant-time: a signature check that returns early leaks how much of
        # a guess was right.
        OpenSSL.secure_compare(expected, signature.to_s)
      end
      private_class_method :signed?

      def self.user_id(user_json)
        id = JSON.parse(user_json.to_s)["id"] or return nil

        Integer(id)
      rescue JSON::ParserError, TypeError, ArgumentError
        nil
      end
      private_class_method :user_id
    end
  end
end
