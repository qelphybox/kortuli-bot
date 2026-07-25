RSpec.describe Booking::Telegram::Handlers do
  subject(:handlers) { described_class.new(repos:, drafts:, owner_id: 42) }

  let(:db) { Booking::DB.connect("sqlite:/") }
  let(:repos) { Booking::Repos.for(db) }
  let(:drafts) { Booking::Telegram::Wizard::Store.new }

  before { repos.clubs.upsert(slug: "demo", name: "Demo Club", adapter: "reservio") }

  def message(text, user_id: 42) = handlers.on_message(user_id:, text:)
  def tap_button(data, user_id: 42, message_id: 7) = handlers.on_callback(user_id:, data:, message_id:)
  def kinds(replies) = replies.map(&:kind)

  describe "who is allowed in" do
    it "turns away anyone who is not the owner" do
      replies = message("/start", user_id: 999)

      expect(replies.first.text).to eq(Booking::Messages.not_for_you)
    end

    it "turns away a stranger's button press too" do
      expect(tap_button("w:cancel", user_id: 999).first.text).to eq(Booking::Messages.not_for_you)
    end

    it "lets everyone in when no owner is configured" do
      open_bot = described_class.new(repos:, drafts:, owner_id: nil)

      expect(open_bot.on_message(user_id: 999, text: "/start").first.text).to include("Padel")
    end
  end

  describe "commands" do
    it "introduces itself on /start" do
      expect(message("/start").first.text).to include("Padel")
    end

    it "tolerates the @botname suffix Telegram adds in groups" do
      expect(message("/start@kortuli_bot").first.text).to include("Padel")
    end

    it "opens the wizard on /watch" do
      replies = message("/watch")

      expect(kinds(replies)).to eq([:send])
      expect(replies.first.text).to eq(Booking::Messages.pick_clubs)
      expect(replies.first.keyboard).not_to be_empty
    end

    it "says so when there is nothing to list" do
      expect(message("/list").first.text).to eq(Booking::Messages.no_watches)
    end

    it "falls back to the help text for anything else" do
      expect(message("what?").first.text).to eq(Booking::Messages.help)
    end
  end

  describe "finishing the wizard" do
    def build_a_watch
      message("/watch")
      tap_button("w:club:demo")
      tap_button("w:next")
      tap_button("w:day:6")
      tap_button("w:next")
      tap_button("w:from:19")
      tap_button("w:to:22")
    end

    it "saves the watch the user assembled" do
      build_a_watch
      watch = repos.watches.for_user(42).first

      expect(watch.club_slugs).to eq(Set["demo"])
      expect(watch.weekdays).to eq(Set[6])
      expect(watch.from_minute).to eq(1140)
      expect(watch.to_minute).to eq(1320)
      expect(watch).to be_active
    end

    it "confirms in place rather than piling up messages" do
      replies = build_a_watch

      expect(kinds(replies)).to eq([:edit])
      expect(replies.first.text).to include("Demo Club")
    end

    it "throws the draft away once it is saved" do
      build_a_watch

      expect(drafts.fetch(42)).to be_nil
    end

    it "only nags when the user tries to skip a required choice" do
      message("/watch")
      replies = tap_button("w:next")

      expect(kinds(replies)).to eq([:alert])
      expect(replies.first.text).to eq(Booking::Messages.pick_at_least_one_club)
    end

    it "redraws the keyboard as choices are made" do
      message("/watch")
      replies = tap_button("w:club:demo")

      expect(kinds(replies)).to eq([:edit])
      expect(replies.first.message_id).to eq(7)
    end

    it "drops the draft when cancelled" do
      message("/watch")
      tap_button("w:cancel")

      expect(drafts.fetch(42)).to be_nil
      expect(repos.watches.for_user(42)).to be_empty
    end
  end

  describe "a button pressed after a restart" do
    it "says the form is gone instead of crashing" do
      replies = tap_button("w:club:demo")

      expect(kinds(replies)).to eq([:alert])
      expect(replies.first.text).to eq(Booking::Messages.wizard_expired)
    end
  end

  describe "managing existing watches" do
    let!(:watch) do
      repos.watches.create(user_id: 42, club_slugs: ["demo"], weekdays: [6], from_minute: 1140, to_minute: 1320)
    end

    it "lists each watch with its own controls" do
      replies = message("/list")

      expect(replies.size).to eq(1)
      expect(replies.first.text).to include("Demo Club")
      expect(replies.first.keyboard.flatten.map(&:data)).to include("l:pause:#{watch.id}", "l:delete:#{watch.id}")
    end

    it "pauses a watch" do
      tap_button("l:pause:#{watch.id}")

      expect(repos.watches.find(watch.id)).not_to be_active
    end

    it "resumes a paused watch" do
      repos.watches.set_active(watch.id, false)
      tap_button("l:resume:#{watch.id}")

      expect(repos.watches.find(watch.id)).to be_active
    end

    it "deletes a watch" do
      tap_button("l:delete:#{watch.id}")

      expect(repos.watches.find(watch.id)).to be_nil
    end

    it "refuses to touch a watch belonging to somebody else" do
      other = repos.watches.create(user_id: 99, club_slugs: ["demo"], weekdays: [6], from_minute: 1140, to_minute: 1320)

      tap_button("l:delete:#{other.id}")

      expect(repos.watches.find(other.id)).not_to be_nil
    end
  end
end
