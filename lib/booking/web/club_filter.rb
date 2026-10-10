require "set"

module Booking
  module Web
    # How the Share screen's switch can narrow the clubs: every one of them,
    # the person's Favourites, or a handful ticked by hand. Module-level for
    # the same reason Submission's lists are — a constant inside Data.define's
    # block would not live where it appears to.
    CLUB_FILTER_MODES = %w[all favourites picked].freeze

    # The Clubs a Rundown speaks for, as picked on the Share screen.
    #
    # A filter rather than a form, like the HourSpan next to it: asking for
    # Favourites without having starred any, or ticking nothing at all, falls
    # back to every club rather than to an empty message. A Rundown that names
    # no club is not something anybody wants to send.
    ClubFilter = Data.define(:mode, :favourites, :picked) do
      def self.from(params, watched_slugs:, favourites:)
        mode = params[:only].to_s
        mode = "all" unless CLUB_FILTER_MODES.include?(mode)

        new(
          mode:,
          # Kept in the club list's own order, so the query string a refresh
          # rebuilds is the same one whatever order the boxes arrived in.
          favourites: watched_slugs & favourites.to_a,
          picked: watched_slugs & Array(params[:clubs]).map(&:to_s)
        )
      end

      def favourites? = mode == "favourites"

      def picked? = mode == "picked"

      # Nil for every club. Otherwise the slugs the Rundown is narrowed to.
      def only
        slugs = { "favourites" => favourites, "picked" => picked }.fetch(mode, [])

        slugs.to_set if slugs.any?
      end

      # Asked for Favourites with nothing starred — said on the screen, so the
      # whole list that came back instead does not read as the filter failing.
      def no_favourites? = favourites? && favourites.empty?

      # Ticked on the screen. With nothing narrowing, everything is: switching
      # to "Pick" starts from the whole list and unticks down from there.
      def includes?(slug) = only.nil? || only.include?(slug)

      def narrow(table) = only ? table.with(rows: table.rows.select { only.include?(_1.club_slug) }) : table

      # What a link back to this screen has to carry for the filter to survive
      # it — the "Whole day" link resets the hours, not the clubs.
      def to_params
        case mode
        when "favourites" then { only: mode }
        when "picked" then { only: mode, clubs: picked }
        else {}
        end
      end
    end
  end
end
