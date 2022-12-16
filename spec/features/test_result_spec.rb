require "json"
require "open3"
require "spec_helper"

RSpec.describe "test results", unless: RSpec::Abq.disable_tests_when_run_by_abq? do
  let(:expected_spawn_msg) {
    {
      "type" => "abq_native_runner_spawned",
      "protocol_version" => {
        "type" => "abq_protocol_version",
        "major" => 0,
        "minor" => 2
      },
      "runner_specification" => {
        "type" => "abq_native_runner_specification",
        "name" => "rspec-abq",
        "version" => RSpec::Abq::VERSION,
        "test_framework" => "rspec",
        "test_framework_version" => RSpec::Core::Version::STRING,
        "language" => RUBY_ENGINE,
        "language_version" => "#{RUBY_VERSION}p#{RUBY_PATCHLEVEL}",
        "host" => RUBY_DESCRIPTION
      }
    }
  }

  def flatten_manifest(abq_manifest)
    # Convert a hierarchial manifest into a list of test cases to run.
    # https://www.notion.so/rwx/Native-Runner-Protocol-0-2-d992ef3b4fde4289b02244c1b89a8cc7#40d10f417e2f47ddadfe8935ae56e9cc
    flat_tests = []
    abq_manifest["members"].each do |member|
      if member["type"] == "test"
        test_case_message = {
          test_case: {
            id: member["id"],
            meta: member["meta"]
          }
        }
        flat_tests << test_case_message
      else
        expect(member["type"]).to eq("group")
        flat_tests.concat((flatten_manifest member))
      end
    end
    flat_tests
  end

  def clean_test_result(test_result)
    test_result["test_result"]["runtime"] = "<cleaned for test>"
    test_result["test_result"]["started_at"] = "<cleaned for test>"
    test_result["test_result"]["finished_at"] = "<cleaned for test>"
    if !test_result["test_result"]["output"].nil?
      test_result["test_result"]["output"] =
        test_result["test_result"]["output"]
          .gsub(/\e\[(\d+)(;\d+)*m/, "") # strip ANSI codes
          .gsub(/\n\s*/, "\n") # strip extra newline spaces, differs between rubies
    end
    test_result
  end

  def assert_test_results_consistent(spec_name, command)
    host = "127.0.0.1"

    # Grab the manifest
    server = TCPServer.new host, 0
    abq_socket = "#{host}:#{server.addr[1]}"
    EnvHelper.with_env("ABQ_SOCKET" => abq_socket, "ABQ_GENERATE_MANIFEST" => abq_socket) do
      `#{command}`
    end

    sock = server.accept
    expect(RSpec::Abq.protocol_read(sock)).to eq(expected_spawn_msg)
    manifest_message = RSpec::Abq.protocol_read(sock)
    expect(manifest_message["type"]).to eq("manifest_success")
    manifest = manifest_message["manifest"]

    sock.close
    server.close

    # Feed the manifest tests through RSpec
    server = TCPServer.new host, 0
    abq_socket = "#{host}:#{server.addr[1]}"
    pid = EnvHelper.with_env("ABQ_SOCKET" => abq_socket) do
      Process.spawn(command)
    end

    sock = server.accept
    expect(RSpec::Abq.protocol_read(sock)).to eq(expected_spawn_msg)

    RSpec::Abq.protocol_write({
      init_meta: manifest["init_meta"],
      fast_exit: false
    }, sock)
    expect(RSpec::Abq.protocol_read(sock)).to eq({})

    # Linearize the manifest, write each test and read its result.
    flat_tests = flatten_manifest manifest
    test_results = flat_tests.map do |test|
      RSpec::Abq.protocol_write(test, sock)
      test_result = RSpec::Abq.protocol_read(sock)
      clean_test_result(test_result)
    end
    expect(JSON.pretty_generate(test_results)).to match_snapshot("test_results_#{spec_name}-#{File.basename(ENV["BUNDLE_GEMFILE"])}")

    sock.close
    server.close

    Process.wait pid
  end

  [
    "failing_specs",
    "successful_specs",
    "pending_specs",
    "raising_specs"
  ].each do |spec_name|
    it "has consistent results for #{spec_name}" do |example|
      assert_test_results_consistent(spec_name, "bundle exec rspec --order defined 'spec/fixture_specs/#{spec_name}.rb'")
    end
  end
end
