RSpec.describe Booking::Telegram::About do
  subject(:about) { described_class.new(api:, logger:) }

  let(:api) { FakeAboutApi.new }
  let(:logged) { [] }
  let(:logger) { ->(line) { logged << line } }

  # Stands in for Telegram::Bot::Api: holds what Telegram would hold, records
  # every write, and can be told to refuse one of them.
  class FakeAboutApi
    attr_reader :writes
    attr_accessor :description, :short_description, :commands

    def initialize(refuse: nil)
      @writes = []
      @refuse = refuse
      @description = ""
      @short_description = ""
      @commands = []
    end

    def get_my_description = Struct.new(:description).new(description)
    def get_my_short_description = Struct.new(:short_description).new(short_description)
    def get_my_commands = commands

    def set_my_description(description:) = write(:description) { self.description = description }
    def set_my_short_description(short_description:) = write(:short_description) { self.short_description = short_description }
    def set_my_commands(commands:) = write(:commands) { self.commands = commands }

    private

    def write(what)
      raise "Too Many Requests" if @refuse == what

      @writes << what
      yield
    end
  end

  it "says what the bot is for, in the chat and on its profile" do
    about.install

    expect(api.description).to eq(Booking::Messages.bot_description)
    expect(api.short_description).to eq(Booking::Messages.bot_short_description)
  end

  it "lists exactly the commands the bot answers" do
    about.install

    expect(api.commands.map { [_1.command, _1.description] }).to eq(Booking::Messages.bot_commands.to_a)
  end

  # The bot restarts on every deploy; a text Telegram already has is read,
  # not written again.
  it "writes nothing that is already there" do
    about.install
    about.install

    expect(api.writes).to eq(%i[description short_description commands])
    expect(logged.last(3)).to all(end_with("unchanged"))
  end

  it "puts back a text somebody changed by hand in @BotFather" do
    about.install
    api.description = "Padel slot watcher for Tbilisi"
    about.install

    expect(api.description).to eq(Booking::Messages.bot_description)
  end

  it "keeps going when Telegram refuses one part" do
    api = FakeAboutApi.new(refuse: :short_description)
    described_class.new(api:, logger:).install

    expect(api.description).to eq(Booking::Messages.bot_description)
    expect(api.commands).not_to be_empty
    expect(logged).to include(a_string_matching(/could not set the short description — RuntimeError/))
  end

  # Telegram's own limits; a longer text is refused outright.
  it "stays within what Telegram accepts" do
    expect(Booking::Messages.bot_description.length).to be <= 512
    expect(Booking::Messages.bot_short_description.length).to be <= 120
    Booking::Messages.bot_commands.each do |command, description|
      expect(command).to match(/\A[a-z0-9_]{1,32}\z/)
      expect(description.length).to be_between(1, 256)
    end
  end
end
