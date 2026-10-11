require "fileutils"
require "json"

module Booking
  module Ops
    # "Is it still running?" for a process that serves nothing anybody can
    # ask. Each process touches a file of its own every INTERVAL; the web reads
    # the age of all three. A file rather than a row, because the bot never
    # touches the database and should not start doing so to say it is alive.
    #
    # It proves the process is up, not that it is doing its job — whether the
    # poll loop still ticks is what each Club's last Poll says.
    class Heartbeat
      INTERVAL = 30
      # Two missed beats and a margin: one slow disk write is not an outage.
      STALE_AFTER = INTERVAL * 3

      Reading = Data.define(:process, :beat_at, :started_at, :pid) do
        def age(now) = beat_at && (now - beat_at).to_i

        def state(now)
          return :missing unless beat_at

          age(now) <= STALE_AFTER ? :up : :stale
        end
      end

      def self.path(dir, process) = File.join(dir, "#{process}.beat")

      def self.read(dir, process)
        path = path(dir, process)
        return Reading.new(process:, beat_at: nil, started_at: nil, pid: nil) unless File.exist?(path)

        body = JSON.parse(File.read(path)) rescue {}
        Reading.new(
          process:,
          beat_at: File.mtime(path).utc,
          started_at: (Time.iso8601(body["started_at"]) rescue nil),
          pid: body["pid"]
        )
      end

      def initialize(dir:, process:, started_at: Clock.now)
        @path = self.class.path(dir, process)
        @body = JSON.generate(started_at: started_at.iso8601, pid: Process.pid)
        # A directory it cannot make costs the dashboard its heartbeat, never
        # the process its boot.
        begin
          FileUtils.mkdir_p(dir)
        rescue SystemCallError
          nil
        end
      end

      def beat
        File.write(@path, @body)
      rescue SystemCallError, IOError
        # A full disk stops the beat, and a stopped beat is exactly what the
        # dashboard should show when the disk is full.
        nil
      end

      # Beats from a thread of its own, so the long poll and the scheduler
      # stay exactly as they were.
      def start
        Thread.new do
          loop do
            beat
            sleep INTERVAL
          end
        end
      end
    end
  end
end
