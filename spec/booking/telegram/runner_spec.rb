RSpec.describe Booking::Telegram::Runner do
  subject(:runner) { described_class.new(token: "t", handlers:, owner_id: 42, logger:, client:, retry_delay: 0) }

  let(:logged) { [] }
  let(:logger) { ->(line) { logged << line } }
  let(:client) { FakeClient.new(raises, updates) }
  let(:raises) { [] }
  let(:updates) { [] }
  let(:handlers) { Booking::Telegram::Handlers.new(app_url: "https://app.test", owner_id: 42) }

  # Stands in for Telegram::Bot::Client. Each entry in `raises` is thrown by one
  # call to .run; once they are exhausted the block is invoked normally and the
  # bot it yields replays `updates`, so `listen` returns straight away.
  class FakeClient
    attr_reader :attempts, :bot

    def initialize(raises, updates = []) = (@raises = raises.dup; @updates = updates; @attempts = 0)

    def run(_token)
      @attempts += 1
      raise @raises.shift if @raises.any?

      yield(@bot = FakeBot.new(@updates))
    end
  end

  class FakeBot
    def initialize(updates) = @updates = updates

    def api = @api ||= FakeSendApi.new
    def listen(&block) = @updates.each(&block)
  end

  class FakeSendApi
    attr_reader :sent, :answered, :forwarded

    def initialize = (@sent = []; @answered = []; @forwarded = [])

    def send_message(**params) = @sent << params
    def answer_callback_query(**params) = @answered << params
    def forward_message(**params) = @forwarded << params
  end

  def conflict = Telegram::Bot::Exceptions::ResponseError.new(response: FakeResponse.new(409))
  def teapot = Telegram::Bot::Exceptions::ResponseError.new(response: FakeResponse.new(418))

  FakeResponse = Struct.new(:status) do
    def body = %({"error_code":#{status}})
  end

  def message(text, chat_type: "private", from_id: 7, edit_date: nil, message_id: 1)
    Telegram::Bot::Types::Message.new(
      message_id:,
      date: 0,
      chat: { id: 5, type: chat_type },
      from: { id: from_id, is_bot: false, first_name: "K" },
      **(text ? { text: } : {}),
      **(edit_date ? { edit_date: } : {})
    )
  end

  def start_message = message("/start")
  def start_feedback_message = message("/start feedback")
  def feedback_message = message("hey the club is missing", message_id: 77)
  def owner_message = message("test", from_id: 42)
  def photo_message = message(nil, message_id: 99)
  def edited_message = message("wrong text corrected", edit_date: 1)
  def group_message = message("/start", chat_type: "group")

  def stale_button
    Telegram::Bot::Types::CallbackQuery.new(
      id: "q1",
      from: { id: 7, is_bot: false, first_name: "K" },
      chat_instance: "c",
      data: "w:club:demo"
    )
  end

  # Kamal boots the replacement container before it stops the one being
  # replaced, so for a few seconds two processes hold the same bot token and
  # Telegram answers one of them with 409. If the new process dies of it, the
  # old one is never stopped — and the deploy deadlocks waiting for a container
  # that can never become healthy.
  describe "when another instance still holds the token" do
    let(:raises) { [conflict, conflict] }

    it "keeps trying instead of giving up the container" do
      runner.run

      expect(client.attempts).to eq(3)
    end

    it "says what it is waiting for, so a stuck deploy is diagnosable" do
      runner.run

      expect(logged.first).to include("409").or include("another instance")
    end

    it "starts listening once the old instance lets go" do
      runner.run

      expect(logged.last).to include("listening")
    end
  end

  it "does not swallow an API error that retrying cannot fix" do
    stub = described_class.new(
      token: "t", handlers:, owner_id: 42, logger:,
      client: FakeClient.new([teapot]), retry_delay: 0
    )

    expect { stub.run }.to raise_error(Telegram::Bot::Exceptions::ResponseError)
  end

  it "returns rather than looping when the listen loop ends on its own" do
    runner.run

    expect(client.attempts).to eq(1)
  end

  describe "greeting on /start" do
    let(:updates) { [start_message] }

    it "replies in the chat it was spoken to in" do
      runner.run

      expect(client.bot.api.sent.first[:chat_id]).to eq(5)
    end

    # A plain `url` would hand the person off to a browser, where Telegram's
    # signed payload does not exist and nothing can authenticate them.
    it "sends a button that opens the app inside Telegram" do
      runner.run

      button = client.bot.api.sent.first[:reply_markup].inline_keyboard.first.first
      expect(button.web_app.url).to eq("https://app.test")
      expect(button.url).to be_nil
    end

    it "does not forward the /start itself as feedback" do
      runner.run

      expect(client.bot.api.forwarded).to be_empty
    end
  end

  describe "the feedback prompt on /start feedback" do
    let(:updates) { [start_feedback_message] }

    it "replies with the feedback prompt, no button" do
      runner.run

      sent = client.bot.api.sent.first
      expect(sent[:text]).to eq(Booking::Messages.feedback_prompt)
      expect(sent[:reply_markup]).to be_nil
    end
  end

  describe "a feedback message from a stranger" do
    let(:updates) { [feedback_message] }

    it "is forwarded to the owner's chat, from the sender's chat" do
      runner.run

      fwd = client.bot.api.forwarded.first
      expect(fwd[:chat_id]).to eq(42)
      expect(fwd[:from_chat_id]).to eq(5)
      expect(fwd[:message_id]).to eq(77)
    end

    it "is acked back to the sender with one of the pool phrases" do
      runner.run

      ack = client.bot.api.sent.first
      expect(ack[:chat_id]).to eq(5)
      expect(Booking::Messages::FEEDBACK_ACKS).to include(ack[:text])
    end
  end

  describe "a non-text feedback message (a photo)" do
    let(:updates) { [photo_message] }

    it "is forwarded just like text" do
      runner.run

      expect(client.bot.api.forwarded.first[:message_id]).to eq(99)
    end
  end

  describe "an edited message from a stranger" do
    let(:updates) { [edited_message] }

    it "is forwarded again with a marker line above" do
      runner.run

      expect(client.bot.api.sent.first[:chat_id]).to eq(42)
      expect(client.bot.api.sent.first[:text]).to eq(Booking::Messages.feedback_edited)
      expect(client.bot.api.forwarded.first[:chat_id]).to eq(42)
    end

    it "does not ack the sender again" do
      runner.run

      to_sender = client.bot.api.sent.select { _1[:chat_id] == 5 }
      expect(to_sender).to be_empty
    end
  end

  describe "the owner writing to their own bot" do
    let(:updates) { [owner_message] }

    it "is not forwarded — no self-forward in the owner's chat" do
      runner.run

      expect(client.bot.api.forwarded).to be_empty
    end

    it "is not acked" do
      runner.run

      expect(client.bot.api.sent).to be_empty
    end
  end

  # Telegram refuses a web_app button outside a private chat, so a greeting in
  # a group could only be a dead end — and a group is not a place to accept
  # feedback either, since anyone in it would read the ack.
  describe "a message in a group" do
    let(:updates) { [group_message] }

    it "goes unanswered rather than sent a button that cannot open" do
      runner.run

      expect(client.bot.api.sent).to be_empty
      expect(client.bot.api.forwarded).to be_empty
    end
  end

  # The wizard's keyboards are still on screen in a chat that predates its
  # removal. Unanswered, a tapped button spins on the user's phone for good.
  describe "a button left over from the wizard" do
    let(:updates) { [stale_button] }

    it "is answered with nothing, so it stops spinning" do
      runner.run

      expect(client.bot.api.answered.first[:callback_query_id]).to eq("q1")
    end

    it "is not replied to in the chat" do
      runner.run

      expect(client.bot.api.sent).to be_empty
    end
  end

  describe "an update that blows up" do
    let(:updates) { [start_message, start_message] }

    it "costs one update, not the process" do
      allow(handlers).to receive(:on_message).and_raise("boom")

      expect { runner.run }.not_to raise_error
      expect(logged.count { _1.include?("update failed") }).to eq(2)
    end
  end

  # ADR-0002 says feedback delivery is fire-and-forget: a broken forward is
  # logged, the ack still goes out, and the process moves on.
  describe "when forward_message throws" do
    let(:updates) { [feedback_message] }

    before do
      allow_any_instance_of(FakeSendApi).to receive(:forward_message)
        .and_raise("owner has not started the bot")
    end

    it "still acks the sender" do
      runner.run

      expect(client.bot.api.sent.first[:chat_id]).to eq(5)
    end

    it "logs the failure so a silent drop is at least visible" do
      runner.run

      expect(logged.count { _1.include?("forward failed") }).to eq(1)
    end
  end
end
