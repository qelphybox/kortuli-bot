module Booking
  module Ops
    # What the machine underneath looks like from inside a container. The
    # data directory is a bind mount, so `df` on it measures the host's own
    # disk — the one the database grows on — and /proc reports the host's
    # load and memory, because Docker does not virtualise either.
    #
    # Every reading is optional: nil means "this machine would not say", which
    # the dashboard prints as such rather than as zero.
    module Host
      module_function

      Disk = Data.define(:total_bytes, :used_bytes, :free_bytes) do
        def used_ratio = total_bytes.positive? ? used_bytes.fdiv(total_bytes) : 0.0
      end

      Memory = Data.define(:total_bytes, :available_bytes) do
        def used_ratio = total_bytes.positive? ? 1 - available_bytes.fdiv(total_bytes) : 0.0
      end

      # Ruby has no statvfs, and `df -P` is POSIX and in every image this runs
      # in. Columns: filesystem, 1K-blocks, used, available, capacity, mount.
      def disk(dir)
        parse_df(IO.popen(["df", "-Pk", dir], err: File::NULL, &:read))
      rescue SystemCallError
        nil
      end

      def parse_df(output)
        _, total, used, free = output.to_s.lines[1]&.split
        return nil unless free

        Disk.new(total_bytes: Integer(total) * 1024, used_bytes: Integer(used) * 1024, free_bytes: Integer(free) * 1024)
      rescue ArgumentError
        nil
      end

      def load_average(path = "/proc/loadavg")
        File.read(path).split.first(3).map(&:to_f)
      rescue SystemCallError
        nil
      end

      def memory(path = "/proc/meminfo")
        fields = File.foreach(path).to_h { |line| [line[/\A\w+/], line[/\d+/].to_i * 1024] }
        return nil unless fields["MemTotal"] && fields["MemAvailable"]

        Memory.new(total_bytes: fields["MemTotal"], available_bytes: fields["MemAvailable"])
      rescue SystemCallError
        nil
      end
    end
  end
end
