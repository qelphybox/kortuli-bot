require "json"
require "strscan"

module Booking
  # sapadelo.com is a directory of padel clubs, and the only one sourced from
  # the clubs themselves: the cover over every court, a pin on the map, the
  # hours and prices a club publishes. It is read into
  # config/club_profiles.yml by `rake sapadelo:import`, by hand, and never by a
  # running process — none of it changes often enough to be worth a request
  # per page view, and a directory going down must not take a screen with it.
  #
  # Only public club pages are read. robots.txt shuts /api, so the data comes
  # from the same HTML a browser is given.
  module Sapadelo
    BASE_URL = "https://sapadelo.com".freeze

    # One listing names every Tbilisi club's neighbourhood at once; a club's
    # own page does not carry it.
    CITY_URL = "#{BASE_URL}/georgia/padel/tbilisi".freeze

    DAYS = %w[mon tue wed thu fri sat sun].freeze

    # Their word for a court with a roof and no walls is "canopy"; ours is the
    # one the clubs use.
    COVERS = { "indoor" => "indoor", "canopy" => "covered", "outdoor" => "outdoor" }.freeze

    module_function

    def club_url(slug) = "#{BASE_URL}/georgia/clubs/#{slug}"

    # Every Tbilisi club's neighbourhood, keyed by sapadelo's slug.
    def areas(html)
      rows = flight_rows(utf8(html))
      found = rows.values.flat_map { hashes(_1) }.select { _1["entityType"] == "club" && _1["slug"] }

      found.each_with_object({}) { |club, out| out[club["slug"]] ||= club["locationLabel"] }
    end

    # One club page as the plain hash config/club_profiles.yml holds. Raises
    # Booking::Error when the page does not look like a club page any more:
    # an import that quietly wrote half a profile would be worse than none.
    def profile(html, source:, area: nil)
      html = utf8(html)
      rows = flight_rows(html)
      props = rows.values.flat_map { hashes(_1) }.find { _1.key?("defaultHours") && _1.key?("courts") }
      raise Error, "#{source}: no club data on the page" unless props

      props = resolve(props, rows)
      place = json_ld_place(html) || {}
      geo = place["geo"] || {}
      padel = Array(props["courts"]).select { _1["sportType"] == "padel" }

      {
        "source" => source,
        "area" => area,
        "address" => place.dig("address", "streetAddress"),
        "phone" => place["telephone"],
        "lat" => geo["latitude"],
        "lng" => geo["longitude"],
        "courts" => padel.map { { "name" => _1["name"], "cover" => COVERS.fetch(_1["coverType"], _1["coverType"]) } },
        "hours" => hours(rows, props["defaultHours"]),
        "prices" => prices(props["pricingRules"])
      }.compact
    end

    # A body off the wire, or out of a file, arrives in whatever encoding
    # the reader guessed; the page itself says UTF-8.
    def utf8(html) = html.dup.force_encoding(Encoding::UTF_8)

    # Next.js streams a page's data into it as `self.__next_f.push([1,"…"])`
    # chunks. Joined, they are the rows React rebuilds the page from — one per
    # line, `id:payload`, the payload JSON, a module reference, or
    # `T<hex byte length>,<text>` — and `"$1f"` inside a payload points at row
    # 1f. Rows that are not JSON are kept as text and never looked at.
    def flight_rows(html)
      chunks = html.scan(/self\.__next_f\.push\(\[1,"((?:[^"\\]|\\.)*)"\]\)/m).map { JSON.parse(%("#{_1.first}")) }
      stream = StringScanner.new(chunks.join.b)
      rows = {}

      until stream.eos?
        unless stream.scan(/([0-9a-f]+):/)
          stream.skip_until(/\n/) || stream.terminate
          next
        end
        id = stream[1]

        if stream.scan(/T([0-9a-f]+),/)
          length = stream[1].to_i(16)
          rows[id] = stream.peek(length).force_encoding(Encoding::UTF_8)
          stream.pos += length
        else
          line = (stream.scan_until(/\n/) || stream.rest.tap { stream.terminate }).chomp.force_encoding(Encoding::UTF_8)
          rows[id] = begin
            JSON.parse(line)
          rescue JSON::ParserError
            line
          end
        end
      end

      rows
    end

    # Follows `"$id"` pointers into the rows they name. The depth cap is for
    # the page that points at itself, which React allows and a recursion
    # would not survive.
    def resolve(value, rows, depth = 0)
      return value if depth > 40

      case value
      when /\A\$([0-9a-f]+)\z/ then rows.key?(::Regexp.last_match(1)) ? resolve(rows[::Regexp.last_match(1)], rows, depth + 1) : value
      when Array then value.map { resolve(_1, rows, depth + 1) }
      when Hash then value.transform_values { resolve(_1, rows, depth + 1) }
      else value
      end
    end

    def hashes(value, found = [])
      case value
      when Hash
        found << value
        value.each_value { hashes(_1, found) }
      when Array then value.each { hashes(_1, found) }
      end
      found
    end

    # The JSON-LD the page carries for search engines: address, telephone and
    # the pin, in a shape somebody promised to keep.
    def json_ld_place(html)
      html.scan(%r{<script type="application/ld\+json"[^>]*>(.*?)</script>}m).each do |(text)|
        graph = Array(JSON.parse(text)["@graph"])
        place = graph.find { _1["@type"] == "SportsActivityLocation" }
        return place if place
      rescue JSON::ParserError
        next
      end
      nil
    end

    # The week as the page prints it, Monday first. Only a club's default
    # hours are in its data; a day that differs exists only as rendered text,
    # in a row keyed by the day's short name. The default stands in for any
    # day the page did not print.
    def hours(rows, default)
      printed = {}
      rows.each_value { day_rows(_1, rows, printed) }
      fallback = default && "#{default["open"]}–#{default["close"]}"

      DAYS.to_h { [_1, printed.fetch(_1, fallback)] }.compact
    end

    # A day renders as ["$","div","mon",{children: [name, hours, …]}]. The
    # first one of each name wins: the opening-hours card comes before any
    # women-only-hours card on the page.
    def day_rows(value, rows, printed)
      return unless value.is_a?(Array)

      if value.size == 4 && value[0] == "$" && DAYS.include?(value[2]) && value[3].is_a?(Hash)
        cells = resolve(value[3]["children"], rows)
        text = cells.is_a?(Array) && cells[1].is_a?(Array) ? cells[1][3]&.dig("children") : nil
        printed[value[2]] ||= text.gsub(/\s*–\s*/, "–") if text.is_a?(String)
      end

      value.each { day_rows(_1, rows, printed) }
    end

    # Padel rules only, in the club's own order, folded together where only
    # the day differs — "60 GEL on Saturday" and "60 GEL on Sunday" are one
    # line to a reader. A rule without days holds every day, and never folds
    # into one with days: a later rule overrides an earlier one, so "60 on
    # weekends" is what undoes "40 at midday" there, even when the base price
    # is 60 too.
    def prices(rules)
      padel = Array(rules).select { _1["sportType"] == "padel" }.sort_by { _1["sortOrder"].to_i }
      folded = padel.each_with_object({}) do |rule, out|
        days = Array(rule["days"])
        key = [rule["amount"], rule["qualifier"], rule["startMinute"], rule["endMinute"], days.empty?]
        out[key] = (out.fetch(key, []) + days).uniq
      end

      folded.map do |(amount, qualifier, start, finish, _), days|
        {
          "gel" => gel(amount),
          "from_price" => (true if qualifier == "from"),
          "from" => start && clock(start),
          "to" => finish && clock(finish),
          "days" => (DAYS & days if days.any?)
        }.compact
      end
    end

    def gel(amount)
      value = amount.to_f
      value == value.round ? value.round : value
    end

    def clock(minute) = format("%02d:%02d", (minute / 60) % 24, minute % 60)
  end
end
