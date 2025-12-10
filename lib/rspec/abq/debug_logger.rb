module RSpec
  module Abq
    # @!visibility private
    module DebugLogger
      # @!visibility private
      RSPEC_ABQ_DEBUG_LOG_DIR = "RSPEC_ABQ_DEBUG_LOG_DIR"

      # @!visibility private
      ABQ_RUNNER = "ABQ_RUNNER"

      class << self
        # @!visibility private
        def enabled?
          ENV.key?(RSPEC_ABQ_DEBUG_LOG_DIR) && !ENV[RSPEC_ABQ_DEBUG_LOG_DIR].to_s.empty?
        end

        # @!visibility private
        def log(message)
          return unless enabled?
          file.puts("[#{timestamp}] #{message}")
          file.flush
        end

        # @!visibility private
        def log_start(operation)
          return nil unless enabled?
          start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          log("START #{operation}")
          start_time
        end

        # @!visibility private
        def log_end(operation, start_time)
          return unless enabled? && start_time
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
          log("END #{operation} (#{format_duration(elapsed)})")
        end

        # @!visibility private
        def log_operation(operation)
          return yield unless enabled?

          start_time = log_start(operation)
          begin
            result = yield
            log_end(operation, start_time)
            result
          rescue => e
            log("ERROR #{operation}: #{e.class} - #{e.message}")
            raise
          end
        end

        # @!visibility private
        def close
          return unless @file
          @file.close
          @file = nil
        end

        private

        def file
          @file ||= begin
            dir = ENV[RSPEC_ABQ_DEBUG_LOG_DIR]
            FileUtils.mkdir_p(dir)
            runner = ENV[ABQ_RUNNER] || "unknown"
            path = File.join(dir, "worker-#{runner}.log")
            File.open(path, "a").tap do |f|
              f.puts("[#{timestamp}] === rspec-abq logger started (pid=#{Process.pid}, runner=#{runner}) ===")
              f.flush
            end
          end
        end

        def timestamp
          Time.now.strftime("%Y-%m-%d %H:%M:%S.%6N")
        end

        def format_duration(seconds)
          if seconds < 1
            "#{(seconds * 1000).round(2)}ms"
          else
            "#{seconds.round(3)}s"
          end
        end
      end
    end
  end
end
