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
        @tags, @meta = Abq.extract_metadata_and_tags(example.metadata)
      end

      # @param example [RSpec::Core::Example]
      def example_finished(example)
        @execution_result = example.metadata[:execution_result]
      end

      # @param example [RSpec::Core::Example]
      def example_failed(example)
        @status =
          if example.execution_result.exception.is_a? RSpec::Expectations::ExpectationNotMetError
            :failure
          else
            :error
          end
      end

      # @param _example [RSpec::Core::Example]
      def example_passed(_example)
        @status = :success
      end

      # @param example [RSpec::Core::Example]
      def example_pending(example)
        @status =
          if example.execution_result.example_skipped?
            :skipped
          else
            :pending
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
      def runtime_ms
        @execution_result.run_time * 1000
      end

      # does nothing, just here to fulfill reporter api
      def example_group_finished(_)
      end
    end
  end
end
