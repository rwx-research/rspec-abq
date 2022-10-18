RSpec.describe RSpec::Abq, unless: RSpec::Abq.disable_tests? do
  host = "127.0.0.1"
  let(:server) { TCPServer.new(host, 0) }
  let(:client_sock) { TCPSocket.new(host, server.addr[1]) }
  let(:server_sock) { server.accept }

  def stringify_keys(hash)
    hash.map { |k, v| [k.to_s, v.is_a?(Hash) ? stringify_keys(v) : v] }.to_h
  end

  after {
    ENV.delete_if { |k, _v| k.start_with? "ABQ" }
    RSpec::Abq.instance_eval { @socket = nil }
  }

  describe ".protocol_write" do
    require "socket"

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

  describe "startup" do
    before do
      ENV["ABQ_SOCKET"] = "#{host}:#{server.addr[1]}"
    end

    after do
      ENV.delete("ABQ_SOCKET")
    end

    describe ".socket" do
      it "reads socket config and initializes handshake" do
        RSpec::Abq.socket
        expect(RSpec::Abq.protocol_read(server_sock)).to(eq(stringify_keys(RSpec::Abq::PROTOCOL_VERSION_MESSAGE)))
      end
    end

    describe "writing manifest" do
      it "recognizes if ABQ_GENERATE_MANIFEST is set" do
        ENV["ABQ_GENERATE_MANIFEST"] = "1"
        expect(RSpec::Abq::Manifest.should_write_manifest?).to be(true)
      end

      it "writes manifest over socket" do
        RSpec::Abq::Manifest.write_manifest([])
        RSpec::Abq.protocol_read(server_sock) # read handshake
        expect(RSpec::Abq.protocol_read(server_sock)).to(eq(stringify_keys(RSpec::Abq::Manifest.generate([]))))
      end
    end
  end
end
