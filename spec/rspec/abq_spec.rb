require "socket"
require "spec_helper"

def stringify_keys(hash)
  hash.map { |k, v| [k.to_s, v.is_a?(Hash) ? stringify_keys(v) : v] }.to_h
end

RSpec.describe RSpec::Abq do
  describe ".setup_after_specs_loaded!", unless: RSpec::Abq.disable_tests_when_run_by_abq? do
    after { ENV.delete_if { |k, v| k.start_with?("ABQ_") } }

    let(:init_message) { {fast_exit: true} }

    before do
      # stub out socket communication
      socket_double = instance_double(TCPSocket)
      allow(socket_double).to receive(:read).with(4)
      allow(socket_double).to receive(:read) { init_message.to_json }
      allow(socket_double).to receive(:write)

      allow(RSpec::Abq).to receive(:socket) { socket_double }
    end

    it "prevents being called twice" do
      RSpec::Abq.setup_after_specs_loaded!
      expect { RSpec::Abq.setup_after_specs_loaded! }.to raise_error(RSpec::Abq::AbqLoadedTwiceError)
    end

    it "if the env var is set, it writes the manifest and quites", :aggregate_failures do
      ENV[RSpec::Abq::ABQ_GENERATE_MANIFEST] = "true"

      expect(RSpec::Abq::Manifest).to receive(:write_manifest)
      expect(RSpec.world).to receive(:wants_to_quit=).with(true)

      if Gem::Version.new(RSpec::Core::Version::STRING) >= Gem::Version.new("3.10.0")
        expect(RSpec.configuration).to receive(:error_exit_code=).with(0)
      end
      expect(RSpec.world).to receive(:non_example_failure=).with(true)
      expect(RSpec::Abq.setup_after_specs_loaded!).to be true
    end

    context "when the init message asks to fast exit" do
      let(:init_message) { {fast_exit: true} }

      it "does nothing", :aggregate_failures do
        expect(RSpec::Abq::Ordering).not_to receive(:setup)
        expect(RSpec::Abq).not_to receive(:fetch_next_example)
        RSpec::Abq.setup_after_specs_loaded!
      end
    end

    context "when the init message is not empty" do
      let(:init_message) { {init_meta: {invalid_but_nonempty: true}} }

      it "sets up ordering and starts testing", :aggregate_failures do
        expect(RSpec::Abq::Ordering).to receive(:setup!).with(stringify_keys(init_message[:init_meta]), anything)
        expect(RSpec::Abq).to receive(:fetch_next_example)
        RSpec::Abq.setup_after_specs_loaded!
      end
    end
  end

  describe "socket communication", unless: RSpec::Abq.disable_tests_when_run_by_abq? do
    host = "127.0.0.1"
    let(:server) { TCPServer.new(host, 0) }
    let(:client_sock) { TCPSocket.new(host, server.addr[1]) }
    let(:server_sock) { server.accept }

    before do |example|
      ENV["ABQ_SOCKET"] = "#{host}:#{server.addr[1]}"
    end

    after do
      ENV.delete_if { |k, _v| k.start_with? "ABQ" }
      RSpec::Abq.instance_eval { @socket = nil }
    end

    describe ".protocol_write" do
      let(:symbol_payload) { {a: 1, b: 2} }

      it "write messages with a 4-byte length header then the payload", :aggregate_failures do
        RSpec::Abq.protocol_write(symbol_payload, client_sock)
        payload_length = symbol_payload.to_json.bytesize
        expect(server_sock.read(4).unpack("N")[0]).to eq(payload_length)
        expect(server_sock.read(payload_length)).to eq(symbol_payload.to_json)
      end
    end

    describe ".protocol_read" do
      it "reads messages with a 4-byte header" do
        msg_payload = '{"a":1,"b":2}'
        client_sock.write([msg_payload.length].pack("N"))
        client_sock.write(msg_payload)

        expect(RSpec::Abq.protocol_read(server_sock)).to eq(JSON.parse(msg_payload))
      end
    end

    describe ".socket" do
      it "reads socket config and initializes handshake" do
        Thread.new {
          RSpec::Abq.socket
        }
        RSpec::Abq.protocol_write({"init_meta" => {"seed" => 4, "ordering_class" => "RSpec::Core::Ordering::Identity"}}, server_sock)
        expect(RSpec::Abq.protocol_read(server_sock)).to(eq(stringify_keys(RSpec::Abq::PROTOCOL_VERSION_MESSAGE)))
      end
    end
  end

  describe RSpec::Abq::Manifest do
    describe ".write_manifest(example_groups)" do
      it "writes manifest over socket" do
        allow(RSpec::Abq).to receive(:protocol_write)
        registry = RSpec.configuration.ordering_registry
        expect(RSpec::Abq).to receive(:protocol_write).with(RSpec::Abq::Manifest.generate([], 1, registry))
        RSpec::Abq::Manifest.write_manifest([], 1, registry)
      end
    end

    # note: more manifest generation tests are in spec/features/integration_spec.rb
  end
end
