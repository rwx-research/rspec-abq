require "json"

# rubocop:disable RSpec/ExampleLength
RSpec.describe "ABQ Integration test", :feature, unless: RSpec::Abq.disable_tests? do
  host = "127.0.0.1"
  ordered_manifest = {"manifest" => {"members" => [{"members" => [{"id" => "./spec/abq/one_specs.rb[1:1]", "meta" => {}, "tags" => %w[bar foo], "type" => "test"}, {"id" => "./spec/abq/one_specs.rb[1:2]", "meta" => {"bar" => 5}, "tags" => ["foo"], "type" => "test"}, {"members" => [{"id" => "./spec/abq/one_specs.rb[1:3:1]", "meta" => {"skip" => "Temporarily skipped with xit"}, "tags" => ["foo"], "type" => "test"}, {"id" => "./spec/abq/one_specs.rb[1:3:2]", "meta" => {}, "tags" => ["foo"], "type" => "test"}], "meta" => {}, "name" => "./spec/abq/one_specs.rb[1:3]", "tags" => ["foo"], "type" => "group"}], "meta" => {}, "name" => "./spec/abq/one_specs.rb[1]", "tags" => [], "type" => "group"}, {"members" => [{"id" => "./spec/abq/two_specs.rb[1:2]", "meta" => {}, "tags" => [], "type" => "test"}, {"members" => [{"id" => "./spec/abq/two_specs.rb[1:3:1]", "meta" => {"skip" => "Temporarily skipped with xdescribe"}, "tags" => [], "type" => "test"}, {"id" => "./spec/abq/two_specs.rb[1:3:2]", "meta" => {"skip" => "Temporarily skipped with xdescribe"}, "tags" => [], "type" => "test"}], "meta" => {"skip" => "Temporarily skipped with xdescribe"}, "name" => "./spec/abq/two_specs.rb[1:3]", "tags" => [], "type" => "group"}], "meta" => {}, "name" => "./spec/abq/two_specs.rb[1]", "tags" => [], "type" => "group"}]}}

  after { ENV.delete_if { |k, v| k.start_with? "ABQ" } }

  it "generates manifest", :aggregate_failures do
    server = TCPServer.new host, 0
    abq_socket = "#{host}:#{server.addr[1]}"
    ENV["ABQ_SOCKET"] = abq_socket
    ENV["ABQ_GENERATE_MANIFEST"] = abq_socket

    `bundle exec rspec --order defined ./spec/abq/*.rb`

    sock = server.accept
    expect(RSpec::Abq.protocol_read(sock)).to eq({"major" => 0, "minor" => 1, "type" => "abq_protocol_version"})
    expect(RSpec::Abq.protocol_read(sock)).to eq(ordered_manifest)
  end

  it "generates manifest with random ordering", :aggregate_failures do
    server = TCPServer.new host, 0
    abq_socket = "#{host}:#{server.addr[1]}"

    ENV["ABQ_SOCKET"] = abq_socket
    ENV["ABQ_GENERATE_MANIFEST"] = abq_socket

    `bundle exec rspec --seed 2 ./spec/abq/*.rb`
    sock = server.accept

    expect(RSpec::Abq.protocol_read(sock)).to eq({"major" => 0, "minor" => 1, "type" => "abq_protocol_version"})
    expect(RSpec::Abq.protocol_read(sock)).not_to eq(ordered_manifest)
  end
end

# rubocop:enable RSpec/ExampleLength
