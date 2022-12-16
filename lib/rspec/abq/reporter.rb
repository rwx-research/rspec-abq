require "time"

module RSpec
  module Abq
    # Realistically we should instead extend [RSpec::Core::Reporter], but
    # there's some indirection there I don't yet understand, so instead just
    # build it up from scratch for now.
    class Reporter
      attr_reader :status
      attr_reader :id
      attr_reader :display_name
      attr_reader :tags
      attr_reader :meta

      # @param example [RSpec::Core::Example]
      def example_started(example)
        @id = example.id
        @example = example
        @display_name = example.metadata[:full_description]
        @tags, @meta = Manifest.extract_metadata_and_tags(example.metadata)
      end

      # @param example [RSpec::Core::Example]
      def example_finished(example)
        @execution_result = example.metadata[:execution_result]
      end

      # @param example [RSpec::Core::Example]
      def example_failed(example)
        execution_exception = example.execution_result.exception
        presenter = RSpec::Core::Formatters::ExceptionPresenter.new execution_exception, example
        exception = execution_exception.class.name.to_s
        exception = "(anonymous error class)" if exception == ""
        backtrace = presenter.formatted_backtrace
        @status =
          if example.execution_result.exception.is_a? RSpec::Expectations::ExpectationNotMetError
            @status = {
              :type => :failure,
              exception:,
              backtrace:,
            }
          else
            @status = {
              :type => :error,
              exception:,
              backtrace:,
            }
          end
      end

      # @param _example [RSpec::Core::Example]
      def example_passed(_example)
        @status = { :type => :success }
      end

      # @param example [RSpec::Core::Example]
      def example_pending(example)
        @status =
          if example.execution_result.example_skipped?
            @status = { :type => :skipped }
          else
            @status = { :type => :pending }
          end
      end

      # @return [String, nil]
      def output
        if @execution_result.exception
          presenter = RSpec::Core::Formatters::ExceptionPresenter.new @execution_result.exception, @example
          return presenter.fully_formatted 1
        end
        nil
      end

      # @return Int
      def runtime_nanos
        ms = @execution_result.run_time * 1_000
        (ms * 1_000_000).round
      end

      # @return { file: String, line: Int }
      def location
        {
          file: @example.metadata[:file_path],
          line: @example.metadata[:line_number],
        }
      end

      # Collect the scope of this example and all parent groups.
      def lineage
        rev_lineage = [@example.metadata[:description]]
        RSpec::Core::Metadata.ascend(@example.metadata).each do |meta|
          rev_lineage << meta[:description]
        end
        rev_lineage.reverse!
        rev_lineage
      end

      # does nothing, just here to fulfill reporter api
      def example_group_finished(_)
      end

      # creates a hash that fits the abq worker result protocol
      def abq_result
        {
          test_result: {
            status: status,
            id: id,
            display_name: display_name,
            output: output,
            runtime: runtime_nanos,
            tags: tags,
            meta: meta,
            location: location,
            started_at: @execution_result.started_at.utc.iso8601,
            finished_at: @execution_result.finished_at.utc.iso8601,
            lineage: lineage,
          }
        }
      end
    end
  end
end
