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
    # @!visibility private
    PROTOCOL_VERSION = {
      type: "abq_protocol_version",
      major: 0,
      minor: 1
    }

    # The [rspec-abq specification](https://www.notion.so/rwx/ABQ-Worker-Native-Test-Runner-IPC-Interface-0959f5a9144741d798ac122566a3d887#8587ee4fd01e41ec880dcbe212562172).
    # @!visibility private
    NATIVE_RUNNER_SPECIFICATION = {
      type: "abq_native_runner_specification",
      name: "rspec-abq",
      version: RSpec::Abq::VERSION,
      test_framework: "rspec",
      test_framework_version: RSpec::Core::Version::STRING,
      language: RUBY_ENGINE,
      language_version: "#{RUBY_VERSION}p#{RUBY_PATCHLEVEL}",
      host: RUBY_DESCRIPTION
    }

    # The [rpsec-abq spawned message](https://www.notion.so/rwx/ABQ-Worker-Native-Test-Runner-IPC-Interface-0959f5a9144741d798ac122566a3d887#8587ee4fd01e41ec880dcbe212562172).
    # Must be sent to ABQ_SOCKET on startup.
    # @!visibility private
    NATIVE_RUNNER_SPAWNED_MESSAGE = {
      type: "abq_native_runner_spawned",
      protocol_version: PROTOCOL_VERSION,
      runner_specification: NATIVE_RUNNER_SPECIFICATION
    }

    # The [ABQ initialization success
    # message](https://www.notion.so/rwx/ABQ-Worker-Native-Test-Runner-IPC-Interface-0959f5a9144741d798ac122566a3d887#538582a3049f4934a5cb563d815c1247)
    # Must be sent after receiving the ABQ initialization message.
    # @!visibility private
    INIT_SUCCESS_MESSAGE = {}

    # Whether this rspec process is running in ABQ mode.
    # @return [Boolean]
    def self.enabled?(env = ENV)
      if env.key?(ABQ_SOCKET) # is rspec being called from abq?
        env[ABQ_RSPEC_PID] ||= Process.pid.to_s # set the pid of the native runner
        env[ABQ_RSPEC_PID] == Process.pid.to_s # and ensure the pid is this process
        # we check the pid to guard against nested rspec calls thinking they're being called from abq
      else
        false
      end
    end

    # Disables tests so we can compare runtime of rspec core vs parallelized version. Additionally, disables tests
    # if forced via ABQ_DISABLE_TESTS env var.
    # @return [Boolean]
    def self.disable_tests_when_run_by_abq?
      enabled? ||
        ENV.key?("ABQ_DISABLE_TESTS")
    end

    # This is the main entry point for abq-rspec, and it's called when the gem is loaded.
    # @!visibility private
    # @return [void]
    def self.setup_extensions_if_enabled!
      return unless enabled?
      Extensions.setup!
    end

    # This is called from World#ordered_example_group
    # and is used to configure rspec based on
    # 1. rspec-abq expected defaults
    # 2. ordering information sent from the worker (e.g. if the test supervisor has random seed 3, we want this runner to also have the same random seed)
    def self.configure_rspec!
      return if @rspec_configured
      @rspec_configured = true

      # ABQ doesn't support writing example status to disk yet.
      # in its simple implementation, status persistance write the status of all tests which ends up hanging under
      # abq because we haven't run most of the tests in @example_group. (maybe the hanging is rspec trying to execute the tests?).
      # In any case: it's disabled.
      # we set this even if the manifest is being generated
      RSpec.configuration.example_status_persistence_file_path = nil

      # if we're generating a manifest, we don't want to do any other setup
      return if !!ENV[ABQ_GENERATE_MANIFEST]

      # after the manfiest has been sent to the worker, the rspec process will quit and the workers will each start a
      # new rspec process

      # enabling colors allows us to pass through nicer error messages
      if Gem::Version.new(RSpec::Core::Version::STRING) >= Gem::Version.new("3.6.0")
        RSpec.configuration.color_mode = :on
      else
        RSpec.configuration.color = true
      end

      # the first message is the init_meta block of the manifest. This is used to share runtime configuration
      # information amongst worker processes. In RSpec, it is used to ensure that random ordering between workers
      # shares the same seed.
      init_message = protocol_read
      protocol_write(INIT_SUCCESS_MESSAGE)

      if init_message["fast_exit"]
        @fast_exit = true
        return
      end

      Ordering.setup!(init_message["init_meta"], RSpec.configuration)
      nil
    end

    # @!visibility private
    # @return [Boolean]
    def self.fast_exit?
      @fast_exit ||= false
    end

    # Creates the socket to communicate with the worker and sends the worker the protocol
    # @!visibility private
    def self.socket
      @socket ||= TCPSocket.new(*ENV[ABQ_SOCKET].split(":")).tap do |socket|
        # Messages sent to/received from the ABQ worker should be done so ASAP.
        # Since we're on a local network, we don't care about packet reduction here.
        socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
        protocol_write(NATIVE_RUNNER_SPAWNED_MESSAGE, socket)
      end
    end

    # These are the metadata keys that rspec uses internally on examples and groups
    # When we want to report custom tags that rspec-users write, we need to remove these from the example metadata
    # @!visibility private
    RESERVED_METADATA_KEYS = Set.new(RSpec::Core::Metadata::RESERVED_KEYS + [:if, :unless])

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

RSpec::Abq.setup_extensions_if_enabled!
