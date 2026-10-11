module Booking
  # Hours somebody has booked themselves at one Club, told to the people they
  # play with: where, when, what it costs, and a link to put it in a calendar.
  #
  # Ours only as a message. We never see the booking itself — the club's own
  # system has it, and our Grid may not have caught up yet — so a Game is
  # whatever the person says they booked, taken or free. Nothing stores it: it
  # lives in the URL that describes it, which is also the link the group gets.
  #
  # One stretch of consecutive hours, because that is what a booking is. Pure,
  # like the Rundown: it decides what goes in, and Messages decides how it
  # reads.
  Game = Data.define(:club_slug, :club_name, :starts_at, :ends_at, :price, :place, :maps_url, :booking_url, :card_url) do
    def hours = ((ends_at - starts_at) / 3600).to_i

    # Where a calendar should say it is: the club, and the street when its
    # Profile names one, so the calendar's own map can find it.
    def location = [club_name, place].compact.uniq.join(", ")

    # The same Game is the same event: adding it twice, or from two phones in
    # one family, updates it rather than doubling it.
    def uid = "#{club_slug}-#{Calendar.stamp(starts_at)}-#{hours}h@kortuli"

    def to_event
      Calendar::Event.new(
        uid:, title: Messages.game_title(self), starts_at:, ends_at:, location:,
        details: Messages.game_details(self), url: card_url
      )
    end
  end
end
