module Booking
  module Web
    # How each City is drawn on the picker's cards: its own name in Georgian,
    # the region it is the centre of, and a line drawing faint behind the
    # name. Static and the picker's alone, so kept here rather than beside the
    # coordinates in Weather::CITIES, which the poller reads too. A city with
    # no entry still gets a card — its name and counts, plain.
    module CityLooks
      Look = Data.define(:native, :region, :art)

      # The drawings sit in a 150×120 box at a card's bottom-right corner:
      # Tbilisi's ridges, the sea at Batumi, a gabled roof for Kutaisi and
      # Rustavi's blocks. Tbilisi has no region line: it is its own.
      ALL = {
        "Tbilisi" => Look.new(native: "თბილისი", region: nil,
                              art: "M10 92 L40 60 L58 74 L84 40 L108 62 L140 30"),
        "Batumi" => Look.new(native: "ბათუმი", region: "Black Sea",
                             art: "M8 80 Q30 66 52 80 T96 80 T140 80 M8 100 Q30 86 52 100 T96 100 T140 100"),
        "Kutaisi" => Look.new(native: "ქუთაისი", region: "Imereti",
                              art: "M10 100 L44 100 L44 56 L75 30 L106 56 L106 100 L140 100"),
        "Rustavi" => Look.new(native: "რუსთავი", region: "Kvemo Kartli",
                              art: "M14 100 L14 50 L38 50 L38 100 M56 100 L56 34 L80 34 L80 100 M98 100 L98 64 L122 64 L122 100")
      }.freeze

      def self.[](city) = ALL[city]
    end
  end
end
