require "fileutils"

module Booking
  module Ops
    # Each process's own copy of what it says on stdout, kept on the data
    # mount so the web can read the other two. Docker keeps the real log, but
    # only for `docker logs`: a container cannot read another's, and handing
    # the web the Docker socket would hand it the host.
    #
    # One file per process, so nobody shares a write position or a rotation:
    # past MAX_BYTES the file becomes `.1` and the previous `.1` is dropped.
    # At a few hundred kilobytes a day that is a couple of weeks of polling.
    class LogFile
      MAX_BYTES = 5 * 1024 * 1024

      def self.path(dir, process) = File.join(dir, "#{process}.log")

      def initialize(path, max_bytes: MAX_BYTES)
        @path = path
        @max_bytes = max_bytes
        @lock = Mutex.new
      end

      # Never raises. This is a copy for reading back; a full disk must cost
      # the copy, not the process that was only trying to say something.
      def write(line)
        @lock.synchronize do
          rotate if File.size?(@path).to_i >= @max_bytes
          File.open(@path, "a") { _1.puts(line) }
        end
      rescue SystemCallError, IOError
        nil
      end

      private

      def rotate
        File.rename(@path, "#{@path}.1")
      end
    end

    # Reads those files back: every process, or one, newest first, narrowed
    # to the lines that contain a phrase or that report something going wrong.
    # Every line starts with the same ISO 8601 UTC stamp, so lines from three
    # files interleave by sorting on the text itself.
    class LogSearch
      PROCESSES = %w[poller bot web].freeze
      # What a line says when something did not go to plan, in the words the
      # code actually uses — see the logger calls under lib/.
      PROBLEM = /\b(failed|crashed|suspect|could not)\b/
      LIMIT = 300

      Line = Data.define(:process, :text) do
        def problem? = PROBLEM.match?(text)

        def stamp = text[/\A\S+/].to_s
      end

      Result = Data.define(:lines, :truncated)

      def initialize(dir:)
        @dir = dir
      end

      def call(query: nil, process: nil, problems: false, limit: LIMIT)
        needle = query.to_s.strip.downcase
        processes = PROCESSES.include?(process) ? [process] : PROCESSES

        matches = processes.flat_map { lines_of(_1) }.select do |line|
          (needle.empty? || line.text.downcase.include?(needle)) && (!problems || line.problem?)
        end
        # Stamps have a one-second grain, so the order a file was written in
        # breaks ties: a tick's lines stay in the order they were said.
        newest = matches.each_with_index.sort_by { |line, i| [line.stamp, i] }.map(&:first).reverse

        Result.new(lines: newest.first(limit), truncated: newest.size > limit)
      end

      private

      def lines_of(process)
        path = LogFile.path(@dir, process)

        ["#{path}.1", path].flat_map do |file|
          File.exist?(file) ? File.foreach(file, chomp: true, encoding: Encoding::UTF_8).map { Line.new(process:, text: _1.scrub) } : []
        end
      end
    end
  end
end
