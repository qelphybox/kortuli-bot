RSpec.describe Booking::Telegram::Handlers do
  subject(:handlers) { described_class.new(app_url: "https://app.test", owner_id: 42) }

  def greeting(user_id: 42) = handlers.on_message(user_id:)

  describe "who is allowed in" do
    it "turns away anyone who is not the owner" do
      expect(greeting(user_id: 999).text).to eq(Booking::Messages.not_for_you)
    end

    it "offers a stranger no way into the app" do
      expect(greeting(user_id: 999).app_url).to be_nil
    end

    it "lets everyone in when no owner is configured" do
      open_bot = described_class.new(app_url: "https://app.test", owner_id: nil)

      expect(open_bot.on_message(user_id: 999).text).to include("Padel")
    end
  end

  describe "the greeting" do
    it "introduces itself" do
      expect(greeting.text).to include("Padel")
    end

    it "carries a button that opens the app" do
      expect(greeting.app_url).to eq("https://app.test")
    end
  end
end
