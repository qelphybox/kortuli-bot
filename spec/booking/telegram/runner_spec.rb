RSpec.describe Booking::Telegram::Runner do
  subject(:runner) { described_class.new(token: "t", handlers: nil, logger:, client:, retry_delay: 0) }

  let(:logged) { [] }
  let(:logger) { ->(line) { logged << line } }
  let(:client) { FakeClient.new(raises) }
  let(:raises) { [] }

  # Stands in for Telegram::Bot::Client. Each entry in `raises` is thrown by one
  # call to .run; once they are exhausted the block is invoked normally and the
  # bot it yields reports no updates, so `listen` returns straight away.
  class FakeClient
    attr_reader :attempts

    def initialize(raises) = (@raises = raises.dup; @attempts = 0)

    def run(_token)
      @attempts += 1
      raise @raises.shift if @raises.any?

      yield(FakeBot.new)
    end
  end

  class FakeBot
    def listen = nil
  end

  def conflict = Telegram::Bot::Exceptions::ResponseError.new(response: FakeResponse.new(409))
  def teapot = Telegram::Bot::Exceptions::ResponseError.new(response: FakeResponse.new(418))

  FakeResponse = Struct.new(:status) do
    def body = %({"error_code":#{status}})
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
    stub = described_class.new(token: "t", handlers: nil, logger:, client: FakeClient.new([teapot]), retry_delay: 0)

    expect { stub.run }.to raise_error(Telegram::Bot::Exceptions::ResponseError)
  end

  it "returns rather than looping when the listen loop ends on its own" do
    runner.run

    expect(client.attempts).to eq(1)
  end
end
