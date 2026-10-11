require "yaml"

module Booking
  # What a Club is like, as opposed to what it has free: the cover over each of
  # its courts, where it is, and the hours and prices it lists. For a person
  # choosing where to play — nothing that decides a Cell reads it. The Grid's
  # Opening hours stay declared in config/clubs.yml; Listed hours here are
  # whatever the club told the directory, and the two can disagree.
  #
  # Read from config/club_profiles.yml, which `rake sapadelo:import` writes.
  # A club with no entry there simply has no Profile.
  ClubProfile = Data.define(:source, :checked_on, :area, :address, :phone, :lat, :lng, :courts, :hours, :prices) do
    def self.load(path = Config.club_profiles_file)
      return {} unless File.exist?(path)

      document = YAML.safe_load_file(path) || {}
      document.fetch("clubs", {}).to_h { |slug, entry| [slug, from(entry, checked_on: document["checked_on"])] }
    end

    def self.from(entry, checked_on: nil)
      new(
        source: entry["source"],
        checked_on: checked_on && Date.iso8601(checked_on.to_s),
        area: entry["area"],
        address: entry["address"],
        phone: entry["phone"],
        lat: entry["lat"],
        lng: entry["lng"],
        courts: Array(entry["courts"]).map { ClubProfile::Court.new(name: _1["name"], cover: _1["cover"]) },
        hours: entry.fetch("hours", {}),
        prices: Array(entry["prices"])
      )
    end

    def located? = !lat.nil? && !lng.nil?

    # Google's documented, keyless way to open a pin — it lands in the Maps
    # app where there is one, and on the website where there is not.
    def maps_url = ("https://www.google.com/maps/search/?api=1&query=#{lat},#{lng}" if located?)

    # [["indoor", 2], ["covered", 3]]: how many courts sit under each cover.
    def covers = courts.map(&:cover).tally.sort_by { |cover, _| ClubProfile::COVERS.index(cover) || ClubProfile::COVERS.size }

    # Consecutive days that keep the same hours, folded, Monday first:
    # [["mon", "fri", "08:00–02:00"], ["sat", "sun", "10:00–02:00"]].
    def hour_runs
      listed = ClubProfile::WEEK.filter_map { |day| [day, hours[day]] if hours[day] }
      runs = listed.chunk_while { |(a, a_hours), (b, b_hours)| a_hours == b_hours && week_index(b) == week_index(a) + 1 }

      runs.map { [_1.first[0], _1.last[0], _1.first[1]] }
    end

    private

    def week_index(day) = ClubProfile::WEEK.index(day)
  end

  class ClubProfile
    # Roofed first: on a wet evening that is the question being asked.
    COVERS = %w[indoor covered outdoor].freeze
    WEEK = %w[mon tue wed thu fri sat sun].freeze

    Court = Data.define(:name, :cover)
  end
end
