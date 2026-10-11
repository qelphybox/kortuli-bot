require "tmpdir"

RSpec.describe Booking::Ops::Heartbeat do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  let(:started_at) { Time.utc(2026, 10, 11, 9, 0, 0) }
  let(:now) { Time.now.utc }

  it "reads back as up right after a beat, with when the process started" do
    described_class.new(dir: @dir, process: "poller", started_at:).beat

    reading = described_class.read(@dir, "poller")

    expect(reading.state(now)).to eq(:up)
    expect(reading.started_at).to eq(started_at)
    expect(reading.pid).to eq(Process.pid)
  end

  it "reads as stale once beats stop arriving" do
    described_class.new(dir: @dir, process: "bot").beat
    long_ago = Time.now - (described_class::STALE_AFTER + 1)
    File.utime(long_ago, long_ago, described_class.path(@dir, "bot"))

    expect(described_class.read(@dir, "bot").state(now)).to eq(:stale)
  end

  it "reads as missing for a process that never beat" do
    expect(described_class.read(@dir, "web").state(now)).to eq(:missing)
  end
end
