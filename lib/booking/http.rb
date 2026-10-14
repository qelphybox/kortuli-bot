require "faraday"
require "faraday/retry"
require "json"
require "zlib"

module Booking
  # The one place that touches the network. Clubs run on shared hosting, so the
  # defaults here are deliberately timid: identify ourselves, give up quickly,
  # and back off rather than retry in a tight loop.
  class Http
    RETRY_STATUSES = [429, 500, 502, 503, 504].freeze

    def initialize(user_agent: Config.user_agent, timeout: Config.http_timeout)
      @connection = Faraday.new do |f|
        # POST is on the list on purpose: every POST we send is a read that a
        # source happens to want as a JSON body (an RPC, a schedule check, a
        # login), so repeating one changes nothing on the other side.
        f.request :retry,
                  max: 3,
                  interval: 1,
                  backoff_factor: 2,
                  retry_statuses: RETRY_STATUSES,
                  methods: %i[get post]
        f.headers["User-Agent"] = user_agent
        f.headers["Accept"] = "application/json"
        f.options.timeout = timeout
        f.options.open_timeout = timeout
      end
    end

    def get_json(url, params = {}, headers: {})
      parse(url, request(url) { @connection.get(url, params, headers) })
    end

    # For sources that read through an RPC rather than a query string. Headers
    # are per request because they are per club: a Supabase key, a bearer.
    def post_json(url, body = {}, headers: {})
      parse(url, request(url) { @connection.post(url, JSON.generate(body), headers.merge("Content-Type" => "application/json")) })
    end

    # For the one request that is not JSON: the discover task scraping a club's
    # landing page for its ids. It goes through here rather than reaching for
    # Faraday directly so that the very first request we ever make to a club
    # still carries the User-Agent that lets them find a human.
    def get_body(url, params = {})
      request(url) { @connection.get(url, params) }
    end

    # For the one source whose token is good only inside the server session
    # that issued it: the page, plus the cookies it set, already in the shape
    # a `Cookie` header wants them back.
    def get_page(url, params = {})
      response = nil
      body = request(url) { response = @connection.get(url, params) }

      [body, cookies(response)]
    end

    private

    # Several Set-Cookie headers arrive joined with ", " — and an `expires`
    # date has a comma of its own, so a cookie starts only where a comma is
    # followed by `name=`. Attributes (path, HttpOnly, …) are not sent back.
    def cookies(response)
      response.headers["set-cookie"].to_s
              .split(/,\s*(?=[^;,=\s]+=)/)
              .map { _1.split(";").first.to_s.strip }
              .reject(&:empty?)
              .join("; ")
    end

    def request(url)
      response = yield
      # Its own type so an adapter holding a login can tell "log in again" from
      # "the club is down" — but still a SourceUnavailable to everyone else.
      raise Adapters::Unauthorized, "#{url} returned #{response.status}" if response.status == 401
      raise Adapters::SourceUnavailable, "#{url} returned #{response.status}" unless response.success?

      decoded(response)
    rescue Faraday::Error, Zlib::Error => e
      # Everything the outside world can do wrong arrives as one exception type,
      # so the poller has exactly one failure mode to reason about.
      raise Adapters::SourceUnavailable, "#{url}: #{e.class} #{e.message}"
    end

    GZIP_MAGIC = "\x1F\x8B".b.freeze

    # Net::HTTP asks for gzip and is meant to inflate it, but the header is no
    # guide to whether it did: Supabase arrived still gzipped, Padel Academy
    # arrived inflated with `content-encoding: gzip` still on it. The body's
    # own first two bytes are the only honest answer, and no JSON, HTML or
    # text body starts with them.
    def decoded(response)
      body = response.body.to_s
      body.b.start_with?(GZIP_MAGIC) ? Zlib.gunzip(body) : body
    end

    def parse(url, body)
      JSON.parse(body)
    rescue JSON::ParserError => e
      # A club that answers HTML where JSON was promised has redesigned or put
      # up an error page. Same failure mode as a timeout, so: same exception.
      raise Adapters::SourceUnavailable, "#{url}: #{e.class} #{e.message}"
    end
  end
end
