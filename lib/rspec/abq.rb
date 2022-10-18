require "set"
require "rspec/core"
require "socket"
require "json"
require_relative "abq/version"
require_relative "abq/manifest"
require_relative "abq/test_case"
require_relative "abq/reporter"
require_relative "abq/extensions"

module RSpec
  # An abq adapter for RSpec!
  module Abq
    # @visibility private
    ABQ_SOCKET = "ABQ_SOCKET"
    # this is set by the outer-most rspec runner to ensure nested rspecs aren't ABQ aware.
    # if we ever want nested ABQ rspec, we'll need to change this.
    ABQ_RSPEC_PID = "ABQ_RSPEC_PID"

    # The [ABQ protocol version message](https://www.notion.so/rwx/ABQ-Worker-Native-Test-Runner-IPC-Interface-0959f5a9144741d798ac122566a3d887#8587ee4fd01e41ec880dcbe212562172).
    # Must be sent to ABQ_SOCKET on startup, if running in ABQ mode.
    # @visibility private
    PROTOCOL_VERSION_MESSAGE = {
      type: "abq_protocol_version",
      major: 0,
      minor: 1
    }

    # Whether this rspec process is running in ABQ mode.
    def self.enabled?(env = ENV)
      env.key?(ABQ_SOCKET) && (!env.key?(ABQ_RSPEC_PID) || env[ABQ_RSPEC_PID] == Process.pid.to_s)
    end

    def self.setup!
      return unless enabled?
      ENV[ABQ_RSPEC_PID] = Process.pid.to_s
      RSpec::Core::ExampleGroup.extend(Abq::Extensions::ExampleGroup)
      RSpec::Core::Runner.prepend(Abq::Extensions::Runner)
    end

    def self.setup_after_specs_loaded!
      if RSpec::Abq::Manifest.should_write_manifest?
        RSpec::Abq::Manifest.write_manifest(RSpec.world.ordered_example_groups)
        # TODO: why can't we just exit(0) here?
        RSpec.world.wants_to_quit = true
        RSpec.configuration.error_exit_code = 0
        RSpec.world.non_example_failure = true
        return
      end

      RSpec.configuration.color_mode = :on
      # disable persisting_example_statuses
      RSpec.configuration.example_status_persistence_file_path = nil
      # TODO: read manifest before fetching first example
      fetch_next_example
    end

    # the socket to communicate with ABQ worker
    def self.socket
      @socket ||= TCPSocket.new(*ENV[ABQ_SOCKET].split(":")).tap do |socket|
        protocol_write(PROTOCOL_VERSION_MESSAGE, socket)
      end
    end

    # disables tests so we can compare runtime of rspec core vs parallelized version
    def self.disable_tests?
      enabled? || ENV.key?("ABQ_DISABLE_TESTS")
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
      attr_reader :target_test_case
    end

    # pulls next example from abq and sets it to #target_test_case
    def self.fetch_next_example
      message = protocol_read
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
    def self.send_test_result_and_advance
      reporter = Reporter.new
      yield(reporter).tap do
        test_result = {
          status: reporter.status,
          id: reporter.id,
          display_name: reporter.display_name,
          output: reporter.output,
          runtime: reporter.runtime_ms,
          tags: reporter.tags,
          meta: reporter.meta
        }
        test_result_msg = {test_result: test_result}
        protocol_write(test_result_msg)
        fetch_next_example
      end
    end
  end
end

RSpec::Abq.setup!
