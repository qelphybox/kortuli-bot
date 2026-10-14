RSpec.describe Booking::Http do
  # The real middleware stack, answering from stubs instead of the network.
  def http_answering(headers)
    stubs = Faraday::Adapter::Test::Stubs.new { _1.get("/Booking/Grid.aspx") { [200, headers, "<html></html>"] } }
    described_class.new(user_agent: "spec", timeout: 1).tap do |http|
      http.instance_variable_get(:@connection).adapter(:test, stubs)
    end
  end

  describe "#get_page" do
    it "hands back the page and the cookie it set, without its attributes" do
      body, cookie = http_answering("set-cookie" => "ASP.NET_SessionId=abc123; path=/; HttpOnly; SameSite=Lax")
                     .get_page("https://booking.padelisland.ge/Booking/Grid.aspx")

      expect(body).to eq("<html></html>")
      expect(cookie).to eq("ASP.NET_SessionId=abc123")
    end

    # Several Set-Cookie headers arrive joined with ", ", and an expiry date
    # carries a comma of its own.
    it "splits several cookies on the commas between them, not inside a date" do
      _, cookie = http_answering("set-cookie" => "a=1; expires=Wed, 14 Oct 2026 00:00:00 GMT; path=/, b=2; HttpOnly")
                  .get_page("https://booking.padelisland.ge/Booking/Grid.aspx")

      expect(cookie).to eq("a=1; b=2")
    end

    it "hands back no cookie when none was set" do
      _, cookie = http_answering({}).get_page("https://booking.padelisland.ge/Booking/Grid.aspx")

      expect(cookie).to eq("")
    end
  end
end
