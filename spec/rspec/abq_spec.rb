require "socket"
require "spec_helper"

def stringify_keys(hash)
  hash.map { |k, v| [k.to_s, v.is_a?(Hash) ? stringify_keys(v) : v] }.to_h
end

RSpec.describe RSpec::Abq do
  describe ".setup_after_specs_loaded!", unless: RSpec::Abq.disable_tests_when_run_by_abq? do
    let(:init_message) { {init_meta: {seed: 124, ordering: "defined"}} }

    before do
      # stub out socket communication
      socket_double = instance_double(TCPSocket)
      allow(socket_double).to receive(:read).with(4)
      allow(socket_double).to receive(:read) { init_message.to_json }
      allow(socket_double).to receive(:write)
      allow(RSpec::Abq).to receive(:socket) { socket_double }
      allow(RSpec::Abq).to receive(:fetch_next_example)
    end

    it "prevents being called twice" do
      EnvHelper.with_reset do
        RSpec::Abq.setup_after_specs_loaded!
        expect { RSpec::Abq.setup_after_specs_loaded! }.to raise_error(RSpec::Abq::AbqLoadedTwiceError)
      end
    end

    context 'with the ABQ_GENERATE_MANIFEST env var set to "true"' do
      around { |example| EnvHelper.with_env(RSpec::Abq::ABQ_GENERATE_MANIFEST => "true") { example.run } }

      it "if the manifest env var is set, it writes the manifest and quits", :aggregate_failures do
        expect(RSpec::Abq::Manifest).to receive(:write_manifest)
        # manifest writing happens before the init message is sent from the worker to the native runner
        expect(RSpec::Abq).not_to receive(:protocol_read)

        expect(RSpec::Abq.setup_after_specs_loaded!).to eq(RSpec::Abq::QUIT_AFTER_MANIFEST_GENERATION)
      end
    end

    context "when the init message asks to fast exit" do
      let(:init_message) { {fast_exit: true} }

      it "does nothing", :aggregate_failures do
        expect(RSpec::Abq::Ordering).not_to receive(:setup)
        expect(RSpec::Abq).not_to receive(:fetch_next_example)
        EnvHelper.with_reset {
          expect(RSpec::Abq.setup_after_specs_loaded!).to eq(RSpec::Abq::QUIT_FAST)
        }
      end
    end

    context "when the init message is not empty" do
      it "sets up ordering and starts testing", :aggregate_failures do
        expect(RSpec::Abq::Ordering).to receive(:setup!).with(stringify_keys(init_message[:init_meta]), anything)
        expect(RSpec::Abq).to receive(:fetch_next_example)
        EnvHelper.with_reset { RSpec::Abq.setup_after_specs_loaded! }
      end
    end

    context "when ordering returns true, indicating rspec should reshuffle" do
      it "sets up ordering and starts testing", :aggregate_failures do
        allow(RSpec::Abq::Ordering).to receive(:setup!).and_return(true)
        expect(RSpec::Abq).to receive(:fetch_next_example)
        EnvHelper.with_reset { expect(RSpec::Abq.setup_after_specs_loaded!).to eq(RSpec::Abq::RESHUFFLE_ORDERING) }
      end
    end

    context "when ordering returns false, indicating rspec must not reshuffle" do
      it "sets up ordering and starts testing", :aggregate_failures do
        allow(RSpec::Abq::Ordering).to receive(:setup!).and_return(false)
        expect(RSpec::Abq).to receive(:fetch_next_example)
        EnvHelper.with_reset { expect(RSpec::Abq.setup_after_specs_loaded!).to be_nil }
      end
    end
  end

  describe "socket communication", unless: RSpec::Abq.disable_tests_when_run_by_abq? do
    host = "127.0.0.1"
    let(:server) { TCPServer.new(host, 0) }
    let(:client_sock) { TCPSocket.new(host, server.addr[1]) }
    let(:server_sock) { server.accept }

    around do |example|
      EnvHelper.with_env("ABQ_SOCKET" => "#{host}:#{server.addr[1]}") do
        example.call
      end
      RSpec::Abq.instance_eval { @socket = nil }
    end

    describe ".protocol_write" do
      let(:symbol_payload) { {a: 1, b: 2} }

      it "write messages with a 4-byte length header then the payload", :aggregate_failures do
        RSpec::Abq.protocol_write(symbol_payload, client_sock)
        payload_length = symbol_payload.to_json.bytesize
        expect(server_sock.read(4).unpack1("N")).to eq(payload_length)
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
        expect(RSpec::Abq.protocol_read(server_sock)).to(eq(stringify_keys(RSpec::Abq::NATIVE_RUNNER_SPAWNED_MESSAGE)))
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

    # note: more manifest generation tests are in spec/features/manifest_spec.rb
  end
end
