require "spec_helper"
RSpec.describe "load order spec", unless: RSpec::Abq.disable_tests_when_run_by_abq? do
  it "runs when .rspec doesn't load the gem", :aggregate_failures do
    host = "127.0.0.1"
    server = TCPServer.new host, 0
    abq_socket = "#{host}:#{server.addr[1]}"
    EnvHelper.with_env("ABQ_SOCKET" => abq_socket, "ABQ_GENERATE_MANIFEST" => abq_socket) do
      # -O loads a specific .rspec file, in this case, ignoring .rspec which requires spec/helper
      `bundle exec rspec -O /dev/null ./spec/fixture_specs/one_specs.rb`
    end

    expect($?).to be_success
  end
end
