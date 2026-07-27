require "rack/test"

RSpec.describe Booking::Web::App do
  include Rack::Test::Methods

  let(:token) { "123456:TEST-TOKEN-do-not-use" }
  let(:sessions) { Booking::Web::Session.new(secret: "a-secret-that-only-the-server-knows") }

  def app
    described_class.tap do |a|
      a.set :telegram_token, token
      a.set :visitor_sessions, sessions
    end
  end

  # Signed the way Telegram signs it. Building the payload here rather than
  # pasting a fixed one keeps auth_date current so the freshness check passes;
  # that the algorithm itself is right is pinned by the vector in the InitData
  # spec, not by this.
  def signed_init_data(user_id:, first_name: "Kirill", signing_token: token)
    fields = {
      "auth_date" => Time.now.to_i.to_s,
      "user" => %({"id":#{user_id},"first_name":"#{first_name}"})
    }
    check = fields.keys.sort.map { "#{_1}=#{fields[_1]}" }.join("\n")
    key = OpenSSL::HMAC.digest("SHA256", "WebAppData", signing_token)
    fields["hash"] = OpenSSL::HMAC.hexdigest("SHA256", key, check)

    URI.encode_www_form(fields)
  end

  describe "arriving without a session" do
    it "is sent to the page that can perform the exchange" do
      get "/"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to end_with("/start")
    end

    it "is not served the page itself" do
      get "/"

      expect(last_response.body).not_to include("data-signed-in")
    end

    # Telegram puts initData in the URL fragment, which never reaches us, so
    # this page exists purely to run the script that posts it back.
    it "can load the exchange page, which asks Telegram for the payload" do
      get "/start"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Telegram.WebApp.initData")
    end
  end

  describe "exchanging initData for a session" do
    # The greeting itself is drawn client-side from Telegram's own SDK, so what
    # this seam can observe is that the exchange produced a session the next
    # request is served on — which is the part that matters.
    it "accepts a payload Telegram signed and remembers who it was" do
      post "/auth", init_data: signed_init_data(user_id: 42)

      expect(last_response.status).to eq(204)

      get "/"
      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("data-signed-in")
    end

    it "refuses a payload signed with a different token" do
      post "/auth", init_data: signed_init_data(user_id: 42, signing_token: "999:WRONG")

      expect(last_response.status).to eq(401)
    end

    it "hands out no session when it refuses" do
      post "/auth", init_data: "user=%7B%22id%22%3A42%7D"

      get "/"
      expect(last_response.status).to eq(302)
    end
  end

  describe "arriving with a session somebody forged" do
    it "is turned away" do
      forged = Booking::Web::Session.new(secret: "not-the-server-secret").issue(42)
      set_cookie("#{Booking::Web::App::COOKIE}=#{forged}")

      get "/"

      expect(last_response.status).to eq(302)
    end
  end

  # kamal-proxy will not route to a container that cannot answer this, so a
  # deploy hangs without it.
  describe "the health endpoint" do
    it "answers without a session" do
      get "/up"

      expect(last_response.status).to eq(200)
    end
  end
end
