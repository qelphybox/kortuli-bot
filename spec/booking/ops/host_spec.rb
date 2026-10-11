require "tmpdir"

RSpec.describe Booking::Ops::Host do
  describe ".parse_df" do
    it "reads the second line of POSIX df output, in 1K blocks" do
      output = <<~DF
        Filesystem     1024-blocks    Used Available Capacity Mounted on
        /dev/sda1         40000000 30000000  10000000      75% /app/data
      DF

      disk = described_class.parse_df(output)

      expect(disk.free_bytes).to eq(10_000_000 * 1024)
      expect(disk.used_ratio).to eq(0.75)
    end

    it "is nil for output it does not recognise" do
      expect(described_class.parse_df("df: /nowhere: No such file or directory\n")).to be_nil
    end
  end

  it "measures a real directory" do
    expect(described_class.disk(Dir.tmpdir).total_bytes).to be_positive
  end

  it "reads the three load averages" do
    Dir.mktmpdir do |dir|
      File.write(path = File.join(dir, "loadavg"), "0.42 0.31 0.20 1/123 4567\n")

      expect(described_class.load_average(path)).to eq([0.42, 0.31, 0.2])
    end
  end

  it "reads memory from meminfo, counting what the kernel could hand out as free" do
    Dir.mktmpdir do |dir|
      File.write(path = File.join(dir, "meminfo"), "MemTotal:        4000 kB\nMemFree:          500 kB\nMemAvailable:    1000 kB\n")

      memory = described_class.memory(path)

      expect([memory.total_bytes, memory.available_bytes]).to eq([4000 * 1024, 1000 * 1024])
      expect(memory.used_ratio).to eq(0.75)
    end
  end

  it "says nothing rather than zero on a machine without /proc" do
    expect(described_class.load_average("/nowhere/loadavg")).to be_nil
    expect(described_class.memory("/nowhere/meminfo")).to be_nil
  end
end
