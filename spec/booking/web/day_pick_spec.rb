require "set"

# The rules of a date's list, without a page around them: which clubs it
# holds for the hours picked, in what order, what the folded ones say and
# which club the hint over them names.
RSpec.describe Booking::Web::DayPick do
  def club(name, free: [], favourite: nil, roofed: false, open_air: false, no_data: false, cover: nil)
    described_class::Club.new(slug: name.downcase.tr(" ", "-"), name:, free: free.to_set, favourite:, roofed:, open_air:,
                              no_data:, cover:)
  end

  let(:hours) { (8..25).to_a }

  def pick(clubs, wanted: [18, 19], rainy: []) = described_class.new(hours:, wanted:, rainy:, clubs:)

  describe "the hours a link asks for" do
    # The hours are this person's to pick: nothing asked for is any time.
    it "opens on any time, and keeps only hours on offer" do
      expect(described_class.wanted(nil, hours)).to eq([])
      expect(described_class.wanted("21,19,99", hours)).to eq([19, 21])
      expect(described_class.wanted("any", hours)).to eq([])
    end

    it "carries any time as no parameter at all" do
      expect(pick([], wanted: []).param).to be_nil
      expect(pick([], wanted: [20]).param).to eq("20")
    end

    it "toggles one hour, and the last one let go is any time" do
      expect(pick([]).toggled(20)).to eq("18,19,20")
      expect(pick([], wanted: [18]).toggled(18)).to be_nil
    end
  end

  describe "who is on the list" do
    let(:both) { club("Both", free: [18, 19]) }
    let(:half) { club("Half", free: [19, 21]) }
    let(:none) { club("None", free: [9]) }

    it "holds only the clubs with every hour picked free" do
      day = pick([both, half, none])

      expect(day.live.map(&:name)).to eq(["Both"])
      expect(day.folded.map { [_1.club.name, _1.why, _1.hours] }).to eq([["Half", :only, [19]], ["None", :last, [9]]])
    end

    it "says where a folded club is free next" do
      expect(pick([half], wanted: [20]).folded.first.to_h.slice(:why, :hours)).to eq(why: :next, hours: [21])
    end

    it "holds every club with anything free, any time" do
      day = pick([both, half, club("Empty"), club("Unread", no_data: true)], wanted: [])

      expect(day.live.map(&:name)).to eq(%w[Both Half])
      expect(day.folded.map(&:why)).to eq(%i[nothing no_data])
    end

    it "names a club's first six hours, and counts the rest" do
      day = pick([club("Long", free: (8..17).to_a)], wanted: [])

      expect(day.chips(day.live.first)).to eq((8..13).to_a)
      expect(day.more(day.live.first)).to eq(4)
    end
  end

  describe "the order" do
    let(:clubs) do
      [club("Alpha", free: [18, 19]), club("Roof", free: [18, 19], roofed: true), club("Zed", free: [18, 19], favourite: 1),
       club("Kus", free: [18, 19], favourite: 0, open_air: true)]
    end

    it "puts the favourites first, in the order they were starred, then the rest by name" do
      expect(pick(clubs).live.map(&:name)).to eq(%w[Kus Zed Alpha Roof])
    end

    # The favourites lead whatever the sky does; behind them, the roofs.
    it "puts the roofs next when the hours picked are wet" do
      expect(pick(clubs, rainy: [19]).live.map(&:name)).to eq(%w[Kus Zed Roof Alpha])
    end

    it "only counts rain over the hours picked" do
      expect(pick(clubs, rainy: [22]).live.map(&:name)).to eq(%w[Kus Zed Alpha Roof])
    end
  end

  describe "the hint" do
    def said(day) = Booking::Messages.day_hint(day).join(" ")

    it "names the first favourite with the hours free on a dry day" do
      day = pick([club("Gone", favourite: 0), club("Hub", free: [18, 19], favourite: 1, roofed: true, cover: "covered")])

      expect(day.hint.kind).to eq(:dry)
      expect(said(day)).to eq("Hub has the whole 18:00–20:00 free.")
    end

    it "asks the favourites with a roof first under rain, and names the one the rain rules out" do
      day = pick([club("Kus", free: [18, 19], favourite: 0, open_air: true),
                  club("Hub", free: [18, 19], favourite: 1, roofed: true, cover: "covered")], rainy: (17..22).to_a)

      expect(day.hint.kind).to eq(:rain)
      expect(said(day)).to eq("Rain 17:00–23:00. Hub (your favourite, covered) has the whole 18:00–20:00 free · Kus is open-air.")
    end

    it "sends to the first roof when every favourite is in the open and wet" do
      day = pick([club("Kus", free: [18, 19], favourite: 0, open_air: true), club("Academy", free: [18, 19], roofed: true)],
                 rainy: [18, 19])

      expect(day.hint.kind).to eq(:roof)
      expect(said(day)).to eq("Rain 18:00–20:00. Your favourites are open-air. Nearest roof: Academy, has the whole 18:00–20:00 free.")
    end

    it "says the favourites have nothing, and how many others do" do
      day = pick([club("Kus", free: [9], favourite: 0), club("Alpha", free: [18, 19]), club("Beta", free: [18, 19])])

      expect(day.hint.kind).to eq(:none)
      expect(said(day)).to eq("No slots at your favourites 18:00–20:00. 2 other clubs have.")
    end

    it "has nothing to say without a favourite on a dry day" do
      expect(pick([club("Alpha", free: [18, 19])]).hint).to be_nil
    end

    # Only the dry hours count, so an open favourite under rain lists those.
    it "lists the dry hours a favourite in the open does have" do
      day = pick([club("Kus", free: [18, 19, 20], favourite: 0, open_air: true)], wanted: [], rainy: [18, 19])

      expect(said(day)).to eq("Rain 18:00–20:00. Kus (your favourite) has 20:00 free.")
    end
  end

  describe "the words over the list" do
    it "says the span, or the hours when they are not one stretch" do
      expect(Booking::Messages.day_span(pick([], wanted: [23, 24]))).to eq("23:00–01:00")
      expect(Booking::Messages.day_span(pick([], wanted: [18, 20]))).to eq("18, 20")
      expect(Booking::Messages.day_span(pick([], wanted: []))).to eq("Any time")
    end

    it "marks the rain on a club in the open, and only there" do
      day = pick([club("Kus", free: [18, 19], open_air: true), club("Unknown", free: [18, 19])], rainy: [19])

      expect(Booking::Messages.day_wet(day, day.live.first)).to eq("☂ rain on court 19")
      expect(Booking::Messages.day_wet(day, day.live.last)).to be_nil
    end
  end
end
