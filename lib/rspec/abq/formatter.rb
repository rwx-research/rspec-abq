require "time"

if Gem::Version.new(RSpec::Core::Version::STRING) < Gem::Version.new("3.6.0")
  # addresses this issue https://github.com/rspec/rspec-core/issues/2471
  require "rspec/core/formatters/console_codes"
end

module RSpec
  module Abq
    # Formatters are used to format RSpec test results. In our case, we're using it to
    # report test results to the abq socket.
    class Formatter
      RSpec::Core::Formatters.register self, :example_passed, :example_pending, :example_failed

      # we don't use the output IO for this formatter (we report everything via the socket)
      def initialize(_output) # rubocop:disable Lint/RedundantInitialize
      end

      # called when an example is completed (this method is aliased to example_pending and example_failed)
      def example_passed(notification)
        Abq.protocol_write(Formatter.abq_result(notification.example))
      end

      alias_method :example_pending, :example_passed
      alias_method :example_failed, :example_passed

      # takes a completed example and creates a abq-compatible test result
      def self.abq_result(example)
        execution_result = example.execution_result
        tags, meta = Manifest.extract_metadata_and_tags(example.metadata)
        test_result = {
          status: status(example),
          id: example.id,
          display_name: example.metadata[:full_description],
          output: if execution_result.exception
                    RSpec::Core::Formatters::ExceptionPresenter
                      .new(execution_result.exception, example)
                      .fully_formatted(1)
                  end,
          runtime: (execution_result.run_time * 1_000_000_000).round,
          tags: tags,
          meta: meta,
          location: {
            file: example.metadata[:file_path],
            line: example.metadata[:line_number]
          },
          started_at: execution_result.started_at.utc.iso8601,
          finished_at: execution_result.finished_at.utc.iso8601,
          lineage: RSpec::Core::Metadata.ascend(example.metadata).map { |meta| meta[:description] }.reverse
        }

        past_rspec_retry_attempts = rspec_retry_attempts(example)
        if past_rspec_retry_attempts
          test_result[:past_attempts] = past_rspec_retry_attempts
        end

        {test_result: test_result}
      end

      private_class_method def self.status(example)
        execution_result = example.execution_result
        exception = execution_result.exception
        case execution_result.status
        when :passed
          {type: :success}
        when :failed
          {
            type:
              if exception.is_a?(RSpec::Expectations::ExpectationNotMetError)
                :failure
              else
                :error
              end,
            exception:
             if exception.class.name.to_s == ""
               "(anonymous error class)"
             else
               exception.class.name.to_s
             end,
            backtrace: RSpec::Core::Formatters::ExceptionPresenter.new(exception, example).formatted_backtrace
          }
        when :pending
          if execution_result.example_skipped?
            {type: :skipped}
          else
            {type: :pending}
          end
        end
      end

      private_class_method def self.rspec_retry_attempts(example)
        return unless defined?(RSpec::Retry)
        return unless example.metadata.key?(:retry_attempts)
        return unless example.metadata.key?(:retry_exceptions)

        retry_attempts = example.metadata[:retry_attempts]
        retry_exceptions = example.metadata[:retry_exceptions]
        return unless retry_attempts > 0

        retry_attempts.times.map do |attempt_index|
          {
            status: {type: :failure},
            id: example.id,
            display_name: example.metadata[:full_description],
            output: retry_exceptions[attempt_index],
            runtime: 0, # rspec-retry does not expose individual durations
            meta: {} # rspec-retry exposes no other metadata beyond attempt and exceptions
          }
        end
      end
    end
  end
end
