require "openssl"

module Booking
  module Web
    # Telegram's initData arrives in the URL fragment, which never reaches a
    # server — the page has to post it back. Doing that on every request would
    # mean decorating every link and every form, and initData ages out anyway.
    # So it is exchanged once for one of these: the same claim ("this is user
    # 42"), signed by us, with an expiry we choose.
    class Session
      # Long enough that a person who opens the app on Monday still has it on
      # Friday, short enough that a cookie copied off a shared device stops
      # working.
      LIFETIME_SECONDS = 30 * 86_400
      DIGEST = "SHA256".freeze
      # Keeps this key apart from anything else derived from the same token,
      # Telegram's own "WebAppData" key for initData included.
      DERIVATION_KEY = "kortuli-session".freeze

      # The signing key comes from the bot token rather than a secret of its
      # own. A separate secret bought nothing: whoever holds the token can mint
      # initData for any user and be issued a cookie honestly through /auth.
      # Rotating the token therefore logs everyone out, which is what a leaked
      # token calls for anyway — and nobody notices, because an unreadable
      # cookie just sends them back through /start for a fresh one.
      def self.for_token(token)
        new(secret: OpenSSL::HMAC.digest(DIGEST, DERIVATION_KEY, token.to_s))
      end

      def initialize(secret:)
        @secret = secret.to_s
      end

      def issue(user_id, now: Clock.now)
        payload = "#{Integer(user_id)}.#{now.to_i + LIFETIME_SECONDS}"

        "#{payload}.#{sign(payload)}"
      end

      def user_id(token, now: Clock.now)
        user_id, expires_at, signature = token.to_s.split(".")
        return nil if signature.nil?

        payload = "#{user_id}.#{expires_at}"
        return nil unless OpenSSL.secure_compare(sign(payload), signature)
        return nil if expires_at.to_i <= now.to_i

        Integer(user_id, exception: false)
      end

      private

      def sign(payload) = OpenSSL::HMAC.hexdigest(DIGEST, @secret, payload)
    end
  end
end
