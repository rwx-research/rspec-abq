require "spec_helper"

RSpec.describe "manifest generation", unless: RSpec::Abq.disable_tests_when_run_by_abq? do
  host = "127.0.0.1"
  expected_spawn_msg = {
    "type" => "abq_native_runner_spawned",
    "protocol_version" => {
      "type" => "abq_protocol_version",
      "major" => 0,
      "minor" => 1
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
  let(:server) { TCPServer.new host, 0 }
  let(:abq_socket) { "#{host}:#{server.addr[1]}" }

  it "generates manifest", :aggregate_failures do
    EnvHelper.with_env("ABQ_SOCKET" => abq_socket, "ABQ_GENERATE_MANIFEST" => abq_socket) do
      `bundle exec rspec --order defined ./spec/fixture_specs/for_manifest/*.rb`
    end

    sock = server.accept
    expect(RSpec::Abq.protocol_read(sock)).to eq(expected_spawn_msg)
    manifest = RSpec::Abq.protocol_read(sock)
    manifest["manifest"]["init_meta"].delete("seed")
    expect(manifest).to match_snapshot("ordered_manifest")
  end

  it "generates manifest with random ordering", :aggregate_failures do
    EnvHelper.with_env("ABQ_SOCKET" => abq_socket, "ABQ_GENERATE_MANIFEST" => abq_socket) do
      `bundle exec rspec --seed 2 ./spec/fixture_specs/for_manifest/*.rb`
    end

    sock = server.accept
    expect(RSpec::Abq.protocol_read(sock)).to eq(expected_spawn_msg)
    manifest = RSpec::Abq.protocol_read(sock)
    # we reset UPDATE_SNAPSHOTS to nil here to ensure that the negated expectation never writes the snapshot
    # workaround for https://github.com/levinmr/rspec-snapshot/issues/33
    EnvHelper.with_env("UPDATE_SNAPSHOTS" => nil) { expect(manifest).not_to match_snapshot("ordered_manifest") }
    expect(manifest["manifest"]["init_meta"]).to eq({"seed" => 2, "ordering" => "random"})
    expect(manifest).to match_snapshot("random_manifest")
  end
end
