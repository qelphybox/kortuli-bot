require "digest"
require "fileutils"
require "faraday/multipart"
require "telegram/bot"

module Booking
  module Telegram
    # The bot's profile photo, from a file in the repository rather than one
    # uploaded to @BotFather by hand.
    #
    # Unlike the description, Telegram's copy cannot be read back and compared:
    # it keeps a recompressed JPEG, never the bytes it was given, and every
    # upload is a new photo. So the bot remembers the digest of what it last
    # uploaded in a stamp on the data mount and uploads only when the file has
    # changed since. Losing the stamp costs one upload; a photo changed by hand
    # in @BotFather stays until the file in the repository changes.
    class Avatar
      def initialize(api:, path:, stamp:, logger: nil)
        @api = api
        @path = path
        @stamp = stamp
        @logger = logger || Booking.default_logger
      end

      def install
        digest = Digest::SHA256.file(@path).hexdigest
        return @logger.call("telegram: profile photo unchanged") if stamped == digest

        # Telegram takes a profile photo only as a fresh multipart upload,
        # referenced from the JSON by the name it was attached under.
        @api.set_my_profile_photo(
          photo: ::Telegram::Bot::Types::InputProfilePhotoStatic.new(photo: "attach://avatar"),
          avatar: Faraday::Multipart::FilePart.new(@path, "image/jpeg")
        )
        stamp(digest)
        @logger.call("telegram: profile photo set")
      rescue StandardError => e
        # A bot with yesterday's face still answers.
        @logger.call("telegram: could not set the profile photo — #{e.class}: #{e.message}")
      end

      private

      def stamped = File.exist?(@stamp) ? File.read(@stamp).strip : nil

      def stamp(digest)
        FileUtils.mkdir_p(File.dirname(@stamp))
        File.write(@stamp, "#{digest}\n")
      end
    end
  end
end
