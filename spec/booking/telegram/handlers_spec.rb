RSpec.describe Booking::Telegram::Handlers do
  subject(:handlers) { described_class.new(app_url: "https://app.test", owner_id: 42) }

  let(:stranger) { 999 }
  let(:owner) { 42 }

  def call(text, user_id: stranger) = handlers.on_message(text:, user_id:)
  def edit(text = "corrected", user_id: stranger) = handlers.on_edit(text:, user_id:)

  describe "/start (no payload)" do
    it "greets with the welcome text and the app button" do
      reply = call("/start")

      expect(reply).to be_a(Booking::Telegram::Handlers::Welcome)
      expect(reply.text).to include("Padel")
      expect(reply.app_url).to eq("https://app.test")
    end

    # The gatekeeping came out in 0da4390 — anyone who has the link is a user.
    it "answers a stranger the same way it answers the owner" do
      expect(call("/start", user_id: stranger).text).to eq(call("/start", user_id: owner).text)
    end
  end

  describe "/start feedback (the pill's deeplink)" do
    it "answers with the feedback prompt, not the welcome" do
      reply = call("/start feedback")

      expect(reply).to be_a(Booking::Telegram::Handlers::Prompt)
      expect(reply.text).to eq(Booking::Messages.feedback_prompt)
    end

    it "answers the owner too — the owner may want to see their own prompt" do
      expect(call("/start feedback", user_id: owner)).to be_a(Booking::Telegram::Handlers::Prompt)
    end
  end

  describe "/feedback typed by hand" do
    it "answers with the same prompt as /start feedback" do
      expect(call("/feedback")).to eq(call("/start feedback"))
    end
  end

  describe "a non-command message from a stranger" do
    it "is forwarded, with a random ack from the pool" do
      reply = call("hey the club is missing")

      expect(reply).to be_a(Booking::Telegram::Handlers::Feedback)
      expect(Booking::Messages::FEEDBACK_ACKS).to include(reply.ack_text)
    end

    it "flags itself as a fresh message, not an edit" do
      expect(call("hi").edited).to eq(false)
    end
  end

  describe "a photo, voice, or other non-text update" do
    # Message#text is nil for these; the runner asks the handler what to do.
    it "is forwarded just like text" do
      expect(call(nil)).to be_a(Booking::Telegram::Handlers::Feedback)
    end
  end

  describe "an unknown /command like /foo" do
    # A slash-prefixed thing the bot does not know is more likely a typo or a
    # thought than a command; treating it as feedback loses nothing.
    it "is forwarded rather than refused" do
      expect(call("/foo")).to be_a(Booking::Telegram::Handlers::Feedback)
    end
  end

  describe "a non-command message from the owner" do
    it "does nothing — no self-forward, no ack" do
      expect(call("test", user_id: owner)).to be_a(Booking::Telegram::Handlers::Silence)
    end
  end

  describe "an edited_message from a stranger" do
    it "is forwarded as an edit, without an ack" do
      reply = edit

      expect(reply).to be_a(Booking::Telegram::Handlers::Feedback)
      expect(reply.edited).to eq(true)
      expect(reply.ack_text).to be_nil
    end

    # A stranger who edits a `/start` (perhaps to correct a typo) is not
    # writing feedback. Forwarding the edit would land in the owner's chat as
    # "hey, an edit of `/start`" — noise for nothing.
    it "does not forward an edit of a command" do
      expect(edit("/start")).to be_a(Booking::Telegram::Handlers::Silence)
      expect(edit("/feedback")).to be_a(Booking::Telegram::Handlers::Silence)
    end
  end

  describe "an edited_message from the owner" do
    it "does nothing" do
      expect(edit("corrected", user_id: owner)).to be_a(Booking::Telegram::Handlers::Silence)
    end
  end
end
