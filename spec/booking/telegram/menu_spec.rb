RSpec.describe Booking::Telegram::Menu do
  subject(:menu) { described_class.new(api:, logger:) }

  let(:api) { FakeMenuApi.new }
  let(:logged) { [] }
  let(:logger) { ->(line) { logged << line } }

  # Stands in for Telegram::Bot::Api, recording the one call this makes.
  class FakeMenuApi
    attr_reader :calls

    def initialize(raises: nil) = (@calls = []; @raises = raises)

    def set_chat_menu_button(**params)
      raise @raises if @raises

      @calls << params
    end
  end

  it "points the menu button at the app" do
    menu.install("https://app.test")

    expect(api.calls.first[:menu_button].web_app.url).to eq("https://app.test")
  end

  it "labels it the same way the greeting's button is labelled" do
    menu.install("https://app.test")

    expect(api.calls.first[:menu_button].text).to eq(Booking::Messages.open_app)
  end

  # No chat_id: the default button is in place before anybody has said anything
  # to the bot, which is the whole point of setting it from here.
  it "sets the default for every private chat rather than one chat's" do
    menu.install("https://app.test")

    expect(api.calls.first).not_to have_key(:chat_id)
  end

  it "says where it pointed it, so a boot log shows the app is reachable" do
    menu.install("https://app.test")

    expect(logged.last).to include("https://app.test")
  end

  # A bot that answers messages without a menu button is worth more than one
  # that refuses to start because Telegram was briefly unreachable.
  describe "when Telegram refuses" do
    let(:api) { FakeMenuApi.new(raises: RuntimeError.new("bad gateway")) }

    it "does not take the process down with it" do
      expect { menu.install("https://app.test") }.not_to raise_error
    end

    it "leaves a line saying the button was not set" do
      menu.install("https://app.test")

      expect(logged.last).to include("bad gateway")
    end
  end
end
