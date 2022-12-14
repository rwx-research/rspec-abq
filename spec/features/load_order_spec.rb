require "spec_helper"
RSpec.describe "load order spec", unless: RSpec::Abq.disable_tests_when_run_by_abq? do
  let(:native_runner_spawn_message) { JSON.parse(RSpec::Abq::NATIVE_RUNNER_SPAWNED_MESSAGE.to_json) }

  it "runs when .rspec doesn't load the gem", :aggregate_failures do
    host = "127.0.0.1"
    server = TCPServer.new host, 0
    abq_socket = "#{host}:#{server.addr[1]}"
    EnvHelper.with_env("ABQ_SOCKET" => abq_socket, "ABQ_GENERATE_MANIFEST" => "true") do
      # -O loads a specific .rspec file, in this case, ignoring .rspec which requires spec/helper
      `bundle exec rspec -O /dev/null ./spec/fixture_specs/successful_specs.rb`
      expect($?).to be_success
    end

    sock = server.accept
    # confirm abq is loading by checking for protocol version message
    expect(RSpec::Abq.protocol_read(sock)).to eq(native_runner_spawn_message)
  end

  it "runs when does loading the gem explicitly", :aggregate_failures do
    host = "127.0.0.1"
    server = TCPServer.new host, 0
    abq_socket = "#{host}:#{server.addr[1]}"
    EnvHelper.with_env("ABQ_SOCKET" => abq_socket, "ABQ_GENERATE_MANIFEST" => "true") do
      # -O loads a specific .rspec file, in this case, ignoring .rspec which requires spec/helper
      `bundle exec rspec --require "rspec/abq" ./spec/fixture_specs/successful_specs.rb`
      expect($?).to be_success
    end

    sock = server.accept
    # confirm abq is loading by checking for protocol version message
    expect(RSpec::Abq.protocol_read(sock)).to eq(native_runner_spawn_message)
  end
end
