require "socket"

RSpec.describe RSpec::Abq do
  context "when using socket communication", unless: RSpec::Abq.disable_tests_when_run_by_abq? do
    host = "127.0.0.1"
    let(:server) { TCPServer.new(host, 0) }
    let(:client_sock) { TCPSocket.new(host, server.addr[1]) }
    let(:server_sock) { server.accept }

    def stringify_keys(hash)
      hash.map { |k, v| [k.to_s, v.is_a?(Hash) ? stringify_keys(v) : v] }.to_h
    end

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
    describe ".should_write_manifest?" do
      it "recognizes if ABQ_GENERATE_MANIFEST is set" do
        ENV.delete("ABQ_GENERATE_MANIFEST")
        expect { ENV["ABQ_GENERATE_MANIFEST"] = "1" }.to(
          change(RSpec::Abq::Manifest, :should_write_manifest?).from(false).to(true)
        )
      end
    end

    describe ".write_manifest(example_groups)" do
      it "writes manifest over socket" do
        allow(RSpec::Abq).to receive(:protocol_write)
        random_ordering = RSpec.configuration.ordering_registry.fetch(:random)
        RSpec::Abq::Manifest.write_manifest([], 1, random_ordering)
        expect(RSpec::Abq).to have_received(:protocol_write).with(RSpec::Abq::Manifest.generate([], 1, random_ordering))
      end
    end

    # note: more manifest generation tests are in spec/features/integration_spec.rb
  end
end
