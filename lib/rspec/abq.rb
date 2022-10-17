require 'set'
module RSpec
  # Provides abq-specific extensions of rspec.
  module Abq
    require 'socket'
    require 'json'

    # @visibility private
    ABQ_SOCKET = "ABQ_SOCKET"

    # this is set by the outer-most rspec runner to ensure nested rspecs aren't ABQ aware.
    # if we ever want nested ABQ rspec, we'll need to change this.
    ABQ_RSPEC_PID = "ABQ_RSPEC_PID"

    # @visibility private
    ABQ_GENERATE_MANIFEST = "ABQ_GENERATE_MANIFEST"

    # @visibility private
    CURRENT_PROTOCOL_VERSION_MAJOR = 0
    # @visibility private
    CURRENT_PROTOCOL_VERSION_MINOR = 1

    # The [ABQ protocol version message](https://www.notion.so/rwx/ABQ-Worker-Native-Test-Runner-IPC-Interface-0959f5a9144741d798ac122566a3d887#8587ee4fd01e41ec880dcbe212562172).
    # Must be sent to ABQ_SOCKET on startup, if running in ABQ mode.
    # @visibility private
    PROTOCOL_VERSION_MESSAGE = {
      :type => "abq_protocol_version",
      :major => CURRENT_PROTOCOL_VERSION_MAJOR,
      :minor => CURRENT_PROTOCOL_VERSION_MINOR,
    }

    def self.setup!
      return unless enabled?
      ENV[ABQ_RSPEC_PID] = Process.pid.to_s
      RSpec::Core::ExampleGroup.extend(Abq::ExampleGroup)
      RSpec::Core::Runner.prepend(Abq::Runner)
    end

    def self.setup_after_specs_loaded!
      if RSpec::Abq::Manifest.should_write_manifest?
        RSpec::Abq::Manifest.write_manifest(RSpec.world.ordered_example_groups)
        RSpec.world.wants_to_quit = true
        RSpec.configuration.error_exit_code = 0
        RSpec.world.non_example_failure = true
        return
      end

      RSpec.configuration.color_mode = :on
      RSpec.configuration.example_status_persistence_file_path = nil
      # TODO: read manifest before fetching first example

      Abq.fetch_next_example
    end

    # the socket to communicate with ABQ worker
    def self.socket
      @socket ||= TCPSocket.new(*ENV[ABQ_SOCKET].split(":")).tap do |socket|
        Abq.protocol_write(PROTOCOL_VERSION_MESSAGE, socket)
      end
    end

    # Whether this rspec process is running in ABQ mode.
    def self.enabled?(env=ENV)
      env.key?(ABQ_SOCKET) && (!env.key?(ABQ_RSPEC_PID) || env[ABQ_RSPEC_PID] == Process.pid.to_s)
    end

    # disables tests so we can compare runtime of rspec core vs parallelized version
    def self.disable_tests?
      enabled? || ENV.key?('ABQ_DISABLE_TESTS')
    end

    # used internally to split off tags from built in rspec metadata
    RESERVED_METADATA_KEYS = Set.new(RSpec::Core::Metadata::RESERVED_KEYS + [:if, :unless])

    # extracts relevant metadata from an a group or example's metadata
    def self.extract_metadata_and_tags(metadata)
      # we use `.dup.reject! because `.reject` raises a warning (because it doesn't dup procs)`
      user_metadata = metadata.dup.reject! { |k, _v| RESERVED_METADATA_KEYS.include?(k) }
      tags_array, metadata_array = user_metadata.partition { |_k, v| v == true }
      [tags_array.map(&:first), metadata_array.to_h]
    end

    class << self
      attr_reader :current_example
    end

    # pulls next example from abq and sets it to #current_example
    def self.fetch_next_example
      message = protocol_read
      @current_example =
        if message == :abq_done
          TestCase.end_marker
        else
          TestCase.new(*message["test_case"].values_at("id", "tags", "meta"))
        end
    end

    # Communication between abq sockets follows the following protocol:
    #   - The first 4 bytes an unsigned 32-bit integer (big-endian) representing
    #     the size of the rest of the message.
    #   - The rest of the message is a JSON-encoded payload.
    class AbqConnBroken < StandardError
    end

    # Writes a message to an Abq socket using the 4-byte header protocol.
    #
    # @param socket [TCPSocket]
    # @param msg
    def self.protocol_write(msg, socket=Abq.socket)
      json_msg = JSON.dump msg
      begin
        socket.write [json_msg.bytesize].pack("N")
        socket.write json_msg
      rescue
        raise AbqConnBroken
      end
    end

    # Writes a message to an Abq socket using the 4-byte header protocol.
    #
    # @param socket [TCPSocket]
    # @return msg
    def self.protocol_read(socket=Abq.socket)
      len_bytes = socket.read 4
      return :abq_done if len_bytes.nil?
      len = len_bytes.unpack("N")[0]
      json_msg = socket.read len
      return :abq_done if json_msg.nil?
      JSON.parse json_msg
    end

    # sends test results to ABQ and advances by one
    def self.send_test_result_and_advance
      reporter = Reporter.new
      yield(reporter).tap do
        test_result = {
          :status => reporter.status,
          :id => reporter.id,
          :display_name => reporter.display_name,
          :output => reporter.output,
          :runtime => reporter.runtime_ms,
          :tags => reporter.tags,
          :meta => reporter.meta
        }
        test_result_msg = { :test_result => test_result }
        Abq.protocol_write(test_result_msg)
        Abq.fetch_next_example
      end
    end

    # A module for abstracting ABQ Manifest
    module Manifest
      # returns true if ABQ wants a manifest
      def self.should_write_manifest?
        !!ENV[ABQ_GENERATE_MANIFEST]
      end

      # writes manifest to abq socket
      def self.write_manifest(ordered_groups)
        Abq.protocol_write(generate(ordered_groups))
      end

      # Generates an ABQ Manifest
      # @param ordered_groups [Array<RSpec::Core::ExampleGroup>] ordered groups to assemble into a manifest
      def self.generate(ordered_groups)
        # TODO: write ordering to manifest meta
        {
          :manifest => {
            :members => ordered_groups.map { |group| to_manifest_group(group) }.compact
          }
        }
      end

      # @visibility private
      # @param group [RSpec::Core::ExampleGroup]
      private_class_method def self.to_manifest_group(group)
        # NB: It's important to write examples first and then children groups,
        # because that's how the runner will execute them.
        members =
          group.ordering_strategy.order(group.filtered_examples).map { |example|
            tags, metadata = Abq.extract_metadata_and_tags(example.metadata)
            {
              :type => "test",
              :id => example.id,
              :tags => tags,
              :meta => metadata,
            }
          }.
          concat(
            group.ordering_strategy.order(group.children).map { |child_group| to_manifest_group(child_group) }.compact
          )
        return nil if members.empty?
        tags, metadata = Abq.extract_metadata_and_tags(group.metadata)
        {
          :type => "group",
          :name => group.id,
          :tags => tags,
          :meta => metadata,
          :members => members,
        }
      end
    end

    # ABQ's representation of a test case
    class TestCase
      def initialize(id, tags, meta)
        @id = id
        @tags = tags
        @meta = meta
        @rerun_file_path, scoped_id = RSpec::Core::Example.parse_id @id
        @scope = self.class.parse_scope(scoped_id || "")
      end

      attr_reader :id
      attr_reader :tags
      attr_reader :meta
      attr_reader :rerun_file_path
      attr_reader :scoped_id

      # Parses a scope n:m:q:r into [n, m, q, r]
      # Invariant of RSpec is that a scope n:m:q:r is contained in a scope n:m:q
      def self.parse_scope(scope)
        scope.split(":")
      end

      # `scope_contains outer inner` is true iff the inner scope is deeper
      # than the outer scope.
      #
      # @param outer [Array<String>] parsed scope
      # @param inner [Array<String>] parsed scope
      def self.scope_contains(outer, inner)
        inner.take(outer.length) == outer
      end

      # `scope_leftover outer inner` returns the partial scopes of `inner`
      # that are deeper than `outer`.
      #
      # @param outer [Array<String>] parsed scope
      # @param inner [Array<String>] parsed scope
      def self.scope_leftover(outer, inner)
        inner[outer.length..-1] || []
      end

      # @param group [RSpec::Core::ExampleGroup]
      def in_group?(group)
        return false if group.metadata[:rerun_file_path] != @rerun_file_path

        group_scope = self.class.parse_scope(group.metadata[:scoped_id])
        self.class.scope_contains(group_scope, @scope)
      end

      # @param group [RSpec::Core::ExampleGroup]
      def directly_in_group?(group)
        return false unless in_group?(group)

        group_scope = self.class.parse_scope(group.metadata[:scoped_id])
        additional_scoping = self.class.scope_leftover(group_scope, @scope)
        raise "#{@id} not inside #{group_scope}, but we thought it was" if additional_scoping.empty?
        additional_scoping.length == 1
      end

      # @param example [RSpec::Core::Example]
      def is_example?(example)
        example.metadata[:rerun_file_path] == @rerun_file_path && self.class.parse_scope(example.metadata[:scoped_id]) == @scope
      end

      # Faux test case to mark end of all tests. Will never match any group or
      # test ID, since the scoped_id is empty.
      def self.end_marker
        @end_marker ||= TestCase.new("[]", [], {})
      end

      # stringify but mostly used for debugging
      def to_s
        "Test case id: #{id}, tags: #{tags}, meta: #{meta}"
      end
    end

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

    module ExampleGroup
      # @private
      # same as .run_examples but using abq
      def run_examples_abq
        ordering_strategy.order(filtered_examples).map do |example|
          next unless Abq.current_example.is_example?(example)
          next if RSpec.world.wants_to_quit

          instance = new(example.inspect_output)
          set_ivars(instance, before_context_ivars)

          Abq.send_test_result_and_advance { |abq_reporter| example.run(instance, abq_reporter) }
        end.all?
      end

      # same as .run but using abq
      def run_abq_mode(reporter)
        # The next test isn't in this group or any child; we can skip
        # over this group entirely.
        return 1 unless Abq.current_example.in_group?(self)

        reporter.example_group_started(self)

        should_run_context_hooks = descendant_filtered_examples.any?
        begin
          RSpec.current_scope = :before_context_hook
          run_before_context_hooks(new('before(:context) hook')) if should_run_context_hooks

          # If the next example to run is on the surface of this group, scan all
          # the examples; otherwise, we just need to check the children groups.
          result_for_this_group =
            if Abq.current_example.directly_in_group? self
              run_examples_abq
            else
              true
            end

          results_for_descendants = ordering_strategy.order(children).map { |child| child.run_abq_mode(reporter) }.all?
          result_for_this_group && results_for_descendants
        rescue Pending::SkipDeclaredInExample => ex
          for_filtered_examples(reporter) { |example| example.skip_with_exception(reporter, ex) }
          true
        rescue Support::AllExceptionsExceptOnesWeMustNotRescue => ex
          # If an exception reaches here, that means we must fail the entire
          # group (otherwise we would have handled the exception locally at an
          # example). Since we know of the examples in the same order as they'll
          # be sent to us from ABQ, we now loop over all the examples, and mark
          # every one that we must run in this group as a failure.
          for_filtered_examples(reporter) do |example|
            next unless Abq.current_example.is_example? example

            Abq.send_test_result_and_advance { |abq_reporter| example.fail_with_exception(abq_reporter, ex) }
          end

          RSpec.world.wants_to_quit = true if reporter.fail_fast_limit_met?
          false
        ensure
          RSpec.current_scope = :after_context_hook
          run_after_context_hooks(new('after(:context) hook')) if should_run_context_hooks
          reporter.example_group_finished(self)
        end
      end
    end

    module Runner
      def setup(_err,_out)
        super

        RSpec::Abq.setup_after_specs_loaded!
      end

      # Runs the provided example groups.
      #
      # @param example_groups [Array<RSpec::Core::ExampleGroup>] groups to run
      # @return [Fixnum] exit status code. 0 if all specs passed,
      #   or the configured failure exit code (1 by default) if specs
      #   failed.
      def run_specs(example_groups)
        examples_count = @world.example_count(example_groups)
        examples_passed = @configuration.reporter.report(examples_count) do |reporter|
          @configuration.with_suite_hooks do
            if examples_count == 0 && @configuration.fail_if_no_examples
              return @configuration.failure_exit_code
            end

            if RSpec::Abq.enabled?
              example_groups.map { |g| g.run_abq_mode(reporter) }.all?
            else
              example_groups.map { |g| g.run(reporter) }.all?
            end
          end
        end

        exit_code(examples_passed)
      end

      private def persist_example_statuses
        if RSpec.configuration.example_status_persistence_file_path
          warn "persisting example status disabled by abq"
        end
      end
    end
  end
end

RSpec::Abq.setup!
