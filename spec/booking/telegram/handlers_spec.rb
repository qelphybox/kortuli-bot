RSpec.describe Booking::Telegram::Handlers do
  subject(:handlers) { described_class.new(app_url: "https://app.test") }

  def greeting(user_id: 42) = handlers.on_message(user_id:)

  describe "the greeting" do
    it "introduces itself" do
      expect(greeting.text).to include("Padel")
    end

    it "carries a button that opens the app" do
      expect(greeting.app_url).to eq("https://app.test")
    end

    # The bot stopped gatekeeping when the app started being useful to
    # anyone with the link. Whoever sends a message gets the same greeting.
    it "answers a stranger the same way it answers the owner" do
      expect(greeting(user_id: 999).text).to eq(greeting(user_id: 42).text)
      expect(greeting(user_id: 999).app_url).to eq(greeting(user_id: 42).app_url)
    end
  end
end
