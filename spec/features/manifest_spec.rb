require "spec_helper"

RSpec.describe "manifest generation", unless: RSpec::Abq.disable_tests_when_run_by_abq? do
  host = "127.0.0.1"
  ordered_manifest = {"manifest" => {"init_meta" => {"ordering" => "defined"}, "members" => [{"members" => [{"id" => "./spec/fixture_specs/for_manifest/one_specs.rb[1:1]", "meta" => {}, "tags" => %w[bar foo], "type" => "test"}, {"id" => "./spec/fixture_specs/for_manifest/one_specs.rb[1:2]", "meta" => {"bar" => 5}, "tags" => ["foo"], "type" => "test"}, {"members" => [{"id" => "./spec/fixture_specs/for_manifest/one_specs.rb[1:3:1]", "meta" => {"skip" => "Temporarily skipped with xit"}, "tags" => ["foo"], "type" => "test"}, {"id" => "./spec/fixture_specs/for_manifest/one_specs.rb[1:3:2]", "meta" => {}, "tags" => ["foo"], "type" => "test"}], "meta" => {}, "name" => "./spec/fixture_specs/for_manifest/one_specs.rb[1:3]", "tags" => ["foo"], "type" => "group"}], "meta" => {}, "name" => "./spec/fixture_specs/for_manifest/one_specs.rb[1]", "tags" => [], "type" => "group"}, {"members" => [{"id" => "./spec/fixture_specs/for_manifest/two_specs.rb[1:2]", "meta" => {}, "tags" => [], "type" => "test"}, {"members" => [{"id" => "./spec/fixture_specs/for_manifest/two_specs.rb[1:3:1]", "meta" => {"skip" => "Temporarily skipped with xdescribe"}, "tags" => [], "type" => "test"}, {"id" => "./spec/fixture_specs/for_manifest/two_specs.rb[1:3:2]", "meta" => {"skip" => "Temporarily skipped with xdescribe"}, "tags" => [], "type" => "test"}], "meta" => {"skip" => "Temporarily skipped with xdescribe"}, "name" => "./spec/fixture_specs/for_manifest/two_specs.rb[1:3]", "tags" => [], "type" => "group"}], "meta" => {}, "name" => "./spec/fixture_specs/for_manifest/two_specs.rb[1]", "tags" => [], "type" => "group"}]}}
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
      "version" => RSpec::Abq::VERSION
    }
  }

  it "generates manifest", :aggregate_failures do
    server = TCPServer.new host, 0
    abq_socket = "#{host}:#{server.addr[1]}"
    EnvHelper.with_env("ABQ_SOCKET" => abq_socket, "ABQ_GENERATE_MANIFEST" => abq_socket) do
      `bundle exec rspec --order defined ./spec/fixture_specs/for_manifest/*.rb`
    end

    sock = server.accept
    expect(RSpec::Abq.protocol_read(sock)).to eq(expected_spawn_msg)
    manifest = RSpec::Abq.protocol_read(sock)
    manifest["manifest"]["init_meta"].delete("seed")
    expect(manifest).to match(ordered_manifest)
  end

  it "generates manifest with random ordering", :aggregate_failures do
    server = TCPServer.new host, 0
    abq_socket = "#{host}:#{server.addr[1]}"

    EnvHelper.with_env("ABQ_SOCKET" => abq_socket, "ABQ_GENERATE_MANIFEST" => abq_socket) do
      `bundle exec rspec --seed 2 ./spec/fixture_specs/for_manifest/*.rb`
    end
    sock = server.accept

    expect(RSpec::Abq.protocol_read(sock)).to eq(expected_spawn_msg)
    manifest = RSpec::Abq.protocol_read(sock)
    expect(manifest).not_to eq(ordered_manifest)
    expect(manifest["manifest"]["init_meta"]).to eq({"seed" => 2, "ordering" => "random"})
  end
end
