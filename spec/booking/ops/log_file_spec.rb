require "tmpdir"

RSpec.describe Booking::Ops::LogFile do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  let(:path) { described_class.path(@dir, "poller") }

  it "appends a line at a time" do
    log = described_class.new(path)

    log.write("one")
    log.write("two")

    expect(File.readlines(path, chomp: true)).to eq(%w[one two])
  end

  it "rolls over to .1 once full, dropping the previous .1" do
    log = described_class.new(path, max_bytes: 10)

    log.write("first line")
    log.write("second line")
    log.write("third line")

    expect(File.read("#{path}.1")).to eq("second line\n")
    expect(File.read(path)).to eq("third line\n")
  end

  # The process was only trying to say something; a full or missing disk
  # must not take it down for that.
  it "swallows a write it cannot make" do
    log = described_class.new(File.join(@dir, "missing", "poller.log"))

    expect { log.write("anything") }.not_to raise_error
  end
end

RSpec.describe Booking::Ops::LogSearch do
  around { |example| Dir.mktmpdir { |dir| @dir = dir; example.run } }

  subject(:search) { described_class.new(dir: @dir) }

  def write(process, *lines, rotated: false)
    path = Booking::Ops::LogFile.path(@dir, process)
    File.write(rotated ? "#{path}.1" : path, lines.map { "#{_1}\n" }.join, encoding: Encoding::UTF_8)
  end

  before do
    write("poller", "2026-10-11T10:00:00Z poll padel-club-2: 388 free", rotated: true)
    write("poller",
          "2026-10-11T10:04:00Z poll padel-club-2: failed — timeout",
          "2026-10-11T10:04:00Z poll kus-tba-padel: 40 free")
    write("bot", "2026-10-11T10:02:00Z telegram: listening")
  end

  def texts(**options) = search.call(**options).lines.map(&:text)

  it "merges every process, newest first, keeping a tick's lines in the order they were said" do
    expect(texts).to eq([
      "2026-10-11T10:04:00Z poll kus-tba-padel: 40 free",
      "2026-10-11T10:04:00Z poll padel-club-2: failed — timeout",
      "2026-10-11T10:02:00Z telegram: listening",
      "2026-10-11T10:00:00Z poll padel-club-2: 388 free"
    ])
  end

  it "says which process said what" do
    expect(search.call(query: "listening").lines.map(&:process)).to eq(["bot"])
  end

  it "finds a phrase whatever its case, in the rotated file too" do
    expect(texts(query: "PADEL-CLUB-2")).to eq([
      "2026-10-11T10:04:00Z poll padel-club-2: failed — timeout",
      "2026-10-11T10:00:00Z poll padel-club-2: 388 free"
    ])
  end

  it "narrows to one process" do
    expect(texts(process: "bot")).to eq(["2026-10-11T10:02:00Z telegram: listening"])
  end

  it "reads every process when asked for one it does not know" do
    expect(texts(process: "../../etc/passwd").size).to eq(4)
  end

  it "narrows to the lines that report trouble" do
    expect(texts(problems: true)).to eq(["2026-10-11T10:04:00Z poll padel-club-2: failed — timeout"])
  end

  it "keeps the newest when there are more than it will show, and says so" do
    result = search.call(limit: 2)

    expect(result.lines.size).to eq(2)
    expect(result.truncated).to be(true)
  end

  it "finds nothing rather than failing when nothing has been logged yet" do
    expect(described_class.new(dir: File.join(@dir, "nowhere")).call.lines).to be_empty
  end
end
