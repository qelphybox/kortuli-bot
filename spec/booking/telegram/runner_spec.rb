RSpec.describe Booking::Telegram::Runner do
  subject(:runner) { described_class.new(token: "t", handlers:, logger:, client:, retry_delay: 0) }

  let(:logged) { [] }
  let(:logger) { ->(line) { logged << line } }
  let(:client) { FakeClient.new(raises, updates) }
  let(:raises) { [] }
  let(:updates) { [] }
  let(:handlers) { Booking::Telegram::Handlers.new(app_url: "https://app.test", owner_id: nil) }

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
    attr_reader :sent, :answered

    def initialize = (@sent = []; @answered = [])

    def send_message(**params) = @sent << params
    def answer_callback_query(**params) = @answered << params
  end

  def conflict = Telegram::Bot::Exceptions::ResponseError.new(response: FakeResponse.new(409))
  def teapot = Telegram::Bot::Exceptions::ResponseError.new(response: FakeResponse.new(418))

  FakeResponse = Struct.new(:status) do
    def body = %({"error_code":#{status}})
  end

  def message(text, chat_type: "private")
    Telegram::Bot::Types::Message.new(
      message_id: 1,
      date: 0,
      chat: { id: 5, type: chat_type },
      from: { id: 42, is_bot: false, first_name: "K" },
      **(text ? { text: } : {})
    )
  end

  def text_message = message("/start")
  def photo_message = message(nil)
  def group_message = message("/start", chat_type: "group")

  def stale_button
    Telegram::Bot::Types::CallbackQuery.new(
      id: "q1",
      from: { id: 42, is_bot: false, first_name: "K" },
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
    stub = described_class.new(token: "t", handlers:, logger:, client: FakeClient.new([teapot]), retry_delay: 0)

    expect { stub.run }.to raise_error(Telegram::Bot::Exceptions::ResponseError)
  end

  it "returns rather than looping when the listen loop ends on its own" do
    runner.run

    expect(client.attempts).to eq(1)
  end

  describe "answering a message" do
    let(:updates) { [text_message] }

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

    it "sends no keyboard at all to somebody who is not allowed in" do
      owned = described_class.new(
        token: "t", handlers: Booking::Telegram::Handlers.new(app_url: "https://app.test", owner_id: 7),
        logger:, client:, retry_delay: 0
      )
      owned.run

      expect(client.bot.api.sent.first[:reply_markup]).to be_nil
    end
  end

  describe "an update that is not a text message" do
    let(:updates) { [photo_message] }

    it "is passed over rather than greeted" do
      runner.run

      expect(client.bot.api.sent).to be_empty
    end
  end

  # Telegram refuses a web_app button outside a private chat, so a greeting in
  # a group could only be a dead end — and would be swallowed as a failed
  # update rather than seen.
  describe "a message in a group" do
    let(:updates) { [group_message] }

    it "goes unanswered rather than sent a button that cannot open" do
      runner.run

      expect(client.bot.api.sent).to be_empty
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
    let(:updates) { [text_message, text_message] }

    it "costs one update, not the process" do
      allow(handlers).to receive(:on_message).and_raise("boom")

      expect { runner.run }.not_to raise_error
      expect(logged.count { _1.include?("update failed") }).to eq(2)
    end
  end
end
