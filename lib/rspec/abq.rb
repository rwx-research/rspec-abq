require "set"
require "rspec/core"
require "socket"
require "json"
require_relative "abq/extensions"
require_relative "abq/manifest"
require_relative "abq/ordering"
require_relative "abq/reporter"
require_relative "abq/test_case"
require_relative "abq/version"

# We nest our patch into RSpec's module -- why not?
module RSpec
  # An abq adapter for RSpec!
  module Abq
    # the socket used to communicate to the abq worker
    # looks like "ip.address.3.4:port" e.g. "0.0.0.0:1234"
    # @!visibility private
    ABQ_SOCKET = "ABQ_SOCKET"

    # the abq worker will set this environmental variable if it needs this process to generate a manifest
    # @!visibility private
    ABQ_GENERATE_MANIFEST = "ABQ_GENERATE_MANIFEST"

    # this is set by the outer-most rspec runner to ensure nested rspecs aren't ABQ aware.
    # if we ever want nested ABQ rspec, we'll need to change this.
    # this env var is unrelated to the abq worker!
    # @!visibility private
    ABQ_RSPEC_PID = "ABQ_RSPEC_PID"

    # The [ABQ protocol version message](https://www.notion.so/rwx/ABQ-Worker-Native-Test-Runner-IPC-Interface-0959f5a9144741d798ac122566a3d887#8587ee4fd01e41ec880dcbe212562172).
    # Must be sent to ABQ_SOCKET on startup.
    # @!visibility private
    PROTOCOL_VERSION_MESSAGE = {
      type: "abq_protocol_version",
      major: 0,
      minor: 1
    }

    # The [ABQ initialization success
    # message](https://www.notion.so/rwx/ABQ-Worker-Native-Test-Runner-IPC-Interface-0959f5a9144741d798ac122566a3d887#538582a3049f4934a5cb563d815c1247)
    # Must be sent after receiving the ABQ initialization message.
    # @!visibility private
    INIT_SUCCESS_MESSAGE = {}

    # Whether this rspec process is running in ABQ mode.
    # @return [Boolean]
    def self.enabled?(env = ENV)
      env.key?(ABQ_SOCKET) && # this is the basic check for rspec being called from an abq worker
        (!env.key?(ABQ_RSPEC_PID) || env[ABQ_RSPEC_PID] == Process.pid.to_s) # and this check ensures that any _nested_ processes do not communicate with the worker.
    end

    # Disables tests so we can compare runtime of rspec core vs parallelized version. Additionally, disables tests
    # if forced via ABQ_DISABLE_TESTS env var.
    # @return [Boolean]
    def self.disable_tests_when_run_by_abq?
      enabled? ||
        ENV.key?("ABQ_DISABLE_TESTS")
    end

    # This is the main entry point for abq-rspec, and it's called when the gem is loaded
    # @!visibility private
    # @return [void]
    def self.setup!
      return unless enabled?
      Extensions.setup!
    end

    # @!visibility private
    # @return [Boolean]
    def self.setup_after_specs_loaded!
      ENV[ABQ_RSPEC_PID] = Process.pid.to_s
      # ABQ doesn't support writing example status to disk yet.
      # in its simple implementation, status persistance write the status of all tests which ends up hanging with under
      # abq because we haven't run most of the tests in this worker. (maybe it's running the tests?). In any case:
      # it's disabled.
      RSpec.configuration.example_status_persistence_file_path = nil

      # before abq can start workers, it asks for a manifest
      if !!ENV[ABQ_GENERATE_MANIFEST] # the abq worker will set this env var if it needs a manifest
        RSpec::Abq::Manifest.write_manifest(RSpec.world.ordered_example_groups, RSpec.configuration.seed, RSpec.configuration.ordering_registry)
        # ... Maybe it's fine to just exit(0)
        RSpec.world.wants_to_quit = true # ask rspec to exit
        RSpec.configuration.error_exit_code = 0 # exit without error
        RSpec.world.non_example_failure = true # exit has nothing to do with tests
        return true
      end

      # after the manfiest has been sent to the worker, the rspec process will quit and the workers will each start a
      # new rspec process

      # enabling colors allows us to pass through nicer error messages
      RSpec.configuration.color_mode = :on

      # the first message is the init_meta block of the manifest. This is used to share runtime configuration
      # information amongst worker processes. In RSpec, it is used to ensure that random ordering between workers
      # shares the same seed, so can be deterministic.
      message = protocol_read
      init_message = message["init_meta"]
      if init_message
        protocol_write(INIT_SUCCESS_MESSAGE)
        # todo: get rid of this unless init_message.empty? as soon as the bug is fixed in abq
        Ordering.setup!(init_message, RSpec.configuration) unless init_message.empty?
        fetch_next_example
      else
        # to support the old protocol, we don't depend on the initialization method, however we don't support random
        # ordering via config, only via a shared command line seed. `abq test -- rspec --seed 4` will pass the
        # deterministic seed to all workers.
        fetch_next_example(message)
      end
      nil
    end

    # Creates the socket to communicate with the worker and sends the worker the protocol
    # @!visibility private
    def self.socket
      @socket ||= TCPSocket.new(*ENV[ABQ_SOCKET].split(":")).tap do |socket|
        protocol_write(PROTOCOL_VERSION_MESSAGE, socket)
      end
    end

    # These are the metadata keys that rspec uses internally on examples and groups
    # When we want to report custom tags that rspec-users write, we need to remove these from the example metadata
    # @!visibility private
    RESERVED_METADATA_KEYS = Set.new(RSpec::Core::Metadata::RESERVED_KEYS + [:if, :unless])

    # Takes group or example metadata and returns a two-element array:
    # a tag is any piece of metadata that has a value of true
    # @return [Array<Array<Symbol>, Hash<Symbol, Object>>] tags and metadata
    # @!visibility private
    def self.extract_metadata_and_tags(metadata)
      # we use `.dup.reject! because `.reject` raises a warning (because it doesn't dup procs)`
      user_metadata = metadata.dup.reject! { |k, _v| RESERVED_METADATA_KEYS.include?(k) }
      tags_array, metadata_array = user_metadata.partition { |_k, v| v == true }
      [tags_array.map(&:first), metadata_array.to_h]
    end

    class << self
      # the target_test_case is the test case the abq worker wants results for
      # @!visibility private
      attr_reader :target_test_case
    end

    # pulls next example from the abq worker and sets it to #target_test_case
    # @!visibility private
    def self.fetch_next_example(message = protocol_read)
      @target_test_case =
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
    def self.protocol_write(msg, socket = Abq.socket)
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
    def self.protocol_read(socket = Abq.socket)
      len_bytes = socket.read 4
      return :abq_done if len_bytes.nil?
      len = len_bytes.unpack1("N")
      json_msg = socket.read len
      return :abq_done if json_msg.nil?
      JSON.parse json_msg
    end

    # sends test results to ABQ and advances by one
    # @!visibility private
    def self.send_test_result_and_advance(&block)
      reporter = Reporter.new
      test_succeeded = block.call(reporter)
      protocol_write(reporter.abq_result)
      fetch_next_example
      # return whether the test succeeded or not
      test_succeeded
    end
  end
end

RSpec::Abq.setup!
