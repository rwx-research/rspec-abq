require "set"
require "rspec/core"
require "socket"
require "json"
require "fileutils"
require "rspec/abq/debug_logger"
require "rspec/abq/extensions"
require "rspec/abq/manifest"
require "rspec/abq/ordering"
require "rspec/abq/formatter"
require "rspec/abq/test_case"
require "rspec/abq/version"

# How does ABQ & its protocol work?
# ======================================
# This is a reframing of some of https://www.notion.so/rwx/Native-Runner-Protocol-0-2-d992ef3b4fde4289b02244c1b89a8cc7
# With pointers to where it is implemented in this codebase.
#
# One or more abq workers each launch a "native runner" (in this case, rspec).
# one of the native runners is designated the one to produce a manifest (via an environmental variable).
#
# Each native runner is passed a socket address as an environmental variable to communicate with its worker.
# The first message sent over the socket is the NATIVE_RUNNER_SPAWNED_MESSAGE, sent from the native runner to the worker.
# (see: `Abq.socket`)
#
# The Manifest
# ------------
# The manifest is used by the abq supervisor to coordinate workers.
# The manifest contains
# - a list of all the tests to run. Each worker will receive a slice of these tests.
# - native-runner specific information for configuring workers. In RSPec's case -- we send ordering information to ensure
#   each instance of rspec orders its specs consistently
#
# The manifest is written in the monkey-patched RSpec::Core::Runner#run_specs method (see `RSpec::Abq::Extensions::Runner`)
#
# After the manifest has been generated and sent to the worker, that native runner quits and is relaunched fresh as as a
# non-manifest-generating worker.
#
# "Normal" Native Runners
# -----------------------
# Non-manifest-generating native runners first perform an initialization handshake, fetching init message from the worker,
# which either has config information or instructions for abq to quit early.
# (see: `Abq.configure_rspec`)
#
# After that, native runners fetch test cases from the worker, and send back test results.
# RSpec will iterate over all tests, but running only those that the worker tells it to run and skipping the rest.
# It will quit when all tests have been iterated over.
#
# Loading rspec-abq
# ========================
# The gem itself is usually loaded when `require spec_helper.rb` is called (either explicitly via `require rspec/abq` or
# implicitly via the Gemfile).
# The spec_helper is usually loaded in one of two ways:
# - via a `--require spec_helper` in the .rspec file, which means the gem is loaded BEFORE specs are loaded
# - or via a `require spec_helper.rb` in the spec itself, which means the gem is loaded WHILE specs are actively being loaded.
#
# In either case: the manifest cannot be written until AFTER specs are loaded, so all that loading the gem does is
# - check if rspec is being run via an abq worker
# - and if so, monkey patch rspec to hook in rspec-abq functionality
#
# Once rspec is patched ...
#
# First run manifest generation against the native runner on a single worker:
# - configure hard-coded rspec settings (Abq.configure_rspec) called from RSpec::Abq::Extensions::World#ordered_example_groups
# - generate the manifest via RSpec::Abq::Extensions::Runner#run_specs
# (the native runner quits)
#
# Then run the native runner again on one or more workers:
# - configure static rspec settings, plus settings fetched from the init_message in the manifest.
# - then fetch and test cases from the worker and send back test results until there are no tests left
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
      minor: 2
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
      DebugLogger.log_operation("perform_handshake!") { perform_handshake! }
      Extensions.setup!
    end

    # Base ABQ error.
    Error = Class.new(StandardError)

    # raised when check_configuration fails
    UnsupportedConfigurationError = Class.new(Error)

    # Failed to connect and initialize handshake.
    ConnectionFailed = Class.new(Error)

    # Communication between abq sockets follows the following protocol:
    #   - The first 4 bytes an unsigned 32-bit integer (big-endian) representing
    #     the size of the rest of the message.
    #   - The rest of the message is a JSON-encoded payload.
    ConnectionBroken = Class.new(Error)

    # raises if RSpec is configured in a way that's incompatible with rspec-abq
    def self.check_configuration!(config)
      if config.fail_fast
        warn("ERROR:\trspec-abq doesn't presently support running with fail-fast enabled.\n" \
                   "\tplease disable fail-fast and try again.")
        fail UnsupportedConfigurationError, "unsupported fail-fast detected."
      end
    end

    # This is called from World#ordered_example_group
    # and is used to configure rspec based on
    # 1. rspec-abq expected defaults
    # 2. ordering information sent from the worker (e.g. if the test supervisor has random seed 3, we want this runner to also have the same random seed)
    def self.configure_rspec!
      return if @rspec_configured
      @rspec_configured = true

      check_configuration!(RSpec.configuration)
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
        RSpec.configuration.tty = true
      end

      # RSpec only adds a default formatter if there are no formatters.
      # Abq::Formatter is used for internal communication over the ABQ protocol, not for $stdout.
      RSpec.configuration.add_formatter(RSpec.configuration.default_formatter) if RSpec.configuration.formatters.empty?

      RSpec.configuration.add_formatter(RSpec::Abq::Formatter)

      # the first message is the init_meta block of the manifest. This is used to share runtime configuration
      # information amongst worker processes. In RSpec, it is used to ensure that random ordering between workers
      # shares the same seed.
      init_message = protocol_read
      DebugLogger.log_operation("protocol_write(INIT_SUCCESS_MESSAGE)") { protocol_write(INIT_SUCCESS_MESSAGE) }

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
    def self.socket(connect_timeout: 5)
      @socket ||= begin
        sock = DebugLogger.log_operation("socket_connect") do
          Socket.tcp(*ENV[ABQ_SOCKET].split(":"), connect_timeout: connect_timeout)
        end
        sock.tap do |socket|
          # Messages sent to/received from the ABQ worker should be done so ASAP.
          # Since we're on a local network, we don't care about packet reduction here.
          socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
          protocol_write(NATIVE_RUNNER_SPAWNED_MESSAGE, socket)
        end
      rescue => e
        DebugLogger.log("socket: connection failed - #{e.class}: #{e.message}")
        raise ConnectionFailed, "Unable to connect to ABQ socket #{ENV[ABQ_SOCKET]}"
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

      alias_method :perform_handshake!, :socket
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

    # Writes a message to an Abq socket using the 4-byte header protocol.
    #
    # @param socket [TCPSocket]
    # @param msg
    def self.protocol_write(msg, socket = Abq.socket)
      json_msg = JSON.dump msg
      msg_type = msg[:type] || msg["type"] || (msg[:test_result] ? "test_result" : "unknown")
      DebugLogger.log_operation("protocol_write(#{msg_type})") do
        socket.write [json_msg.bytesize].pack("N")
        socket.write json_msg
      end
    rescue SystemCallError, IOError => e
      DebugLogger.log("protocol_write: connection broken - #{e.class}: #{e.message}")
      raise ConnectionBroken
    rescue => e
      DebugLogger.log("protocol_write: error - #{e.class}: #{e.message}")
      raise Error
    end

    # Writes a message to an Abq socket using the 4-byte header protocol.
    #
    # @param socket [TCPSocket]
    # @return msg
    def self.protocol_read(socket = Abq.socket, context: nil)
      len_bytes = DebugLogger.log_operation("protocol_read(#{context || "unknown"}::len)") { socket.read 4 }
      return :abq_done if len_bytes.nil?

      len = len_bytes.unpack1("N")
      json_msg = DebugLogger.log_operation("protocol_read(#{context || "unknown"}::msg)") { socket.read len }
      return :abq_done if json_msg.nil?

      JSON.parse json_msg
    rescue SystemCallError, IOError => e
      DebugLogger.log("protocol_read: connection broken - #{e.class}: #{e.message}")
      raise ConnectionBroken
    rescue => e
      DebugLogger.log("protocol_read: error - #{e.class}: #{e.message}")
      raise Error
    end
  end
end

RSpec::Abq.setup_extensions_if_enabled!
