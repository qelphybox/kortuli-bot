require "faraday"
require "faraday/retry"
require "json"

module Booking
  # The one place that touches the network. Clubs run on shared hosting, so the
  # defaults here are deliberately timid: identify ourselves, give up quickly,
  # and back off rather than retry in a tight loop.
  class Http
    RETRY_STATUSES = [429, 500, 502, 503, 504].freeze

    def initialize(user_agent: Config.user_agent, timeout: Config.http_timeout)
      @connection = Faraday.new do |f|
        f.request :retry,
                  max: 3,
                  interval: 1,
                  backoff_factor: 2,
                  retry_statuses: RETRY_STATUSES,
                  methods: [:get]
        f.headers["User-Agent"] = user_agent
        f.headers["Accept"] = "application/json"
        f.options.timeout = timeout
        f.options.open_timeout = timeout
      end
    end

    def get_json(url, params = {})
      JSON.parse(get_body(url, params))
    rescue JSON::ParserError => e
      # A club that answers HTML where JSON was promised has redesigned or put
      # up an error page. Same failure mode as a timeout, so: same exception.
      raise Adapters::SourceUnavailable, "#{url}: #{e.class} #{e.message}"
    end

    # For the one request that is not JSON: the discover task scraping a club's
    # landing page for its ids. It goes through here rather than reaching for
    # Faraday directly so that the very first request we ever make to a club
    # still carries the User-Agent that lets them find a human.
    def get_body(url, params = {})
      response = @connection.get(url, params)
      raise Adapters::SourceUnavailable, "#{url} returned #{response.status}" unless response.success?

      response.body
    rescue Faraday::Error => e
      # Everything the outside world can do wrong arrives as one exception type,
      # so the poller has exactly one failure mode to reason about.
      raise Adapters::SourceUnavailable, "#{url}: #{e.class} #{e.message}"
    end
  end
end
