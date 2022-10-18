RSpec.describe RSpec::Abq, :unless => RSpec::Abq.disable_tests? do
  host = '127.0.0.1'
  after {
    ENV.delete_if { |k, _v| k.start_with? 'ABQ' }
    RSpec::Abq.instance_eval { @socket = nil }

  }

  describe "protocol_write" do
    require 'socket'

    it "write messages with a 4-byte header" do
      server = TCPServer.new host, 0
      client_sock = TCPSocket.new host, server.addr[1]
      server_sock = server.accept

      RSpec::Abq.protocol_write({ :a =>  1, :b =>  2 }, client_sock)
      size = ((server_sock.read 4).unpack "N")[0]

      expect(size).to eq(13)
    end

    it "write messages with payload" do
      server = TCPServer.new host, 0
      client_sock = TCPSocket.new host, server.addr[1]
      server_sock = server.accept

      RSpec::Abq.protocol_write({ :a => 1, :b =>  2 }, client_sock)
      expected_payload = '{"a":1,"b":2}'

      size = ((server_sock.read 4).unpack "N")[0]
      expect(size).to eq(expected_payload.length)

      payload = server_sock.read(expected_payload.length)
      expect(payload).to eq(expected_payload)
    end

    it "reads messages with a 4-byte header" do
      server = TCPServer.new host, 0
      client_sock = TCPSocket.new host, server.addr[1]
      server_sock = server.accept

      msg_payload = '{"a":1,"b":2}'
      msg_size = [msg_payload.length].pack("N")
      client_sock.write msg_size
      client_sock.write msg_payload

      msg = RSpec::Abq.protocol_read server_sock

      expect(msg.size).to eq(2)
      expect(msg["a"]).to eq(1)
      expect(msg["b"]).to eq(2)
    end
  end

  describe "config" do
    def stringify_keys(hash)
      hash.map { |k, v| [k.to_s, v.is_a?(Hash) ? stringify_keys(v) : v] }.to_h
    end

    it "recognizes if ABQ_SOCKET is set" do
      server = TCPServer.new host, 0
      ENV["ABQ_SOCKET"] = "#{host}:#{server.addr[1]}"

      protocl_version_message_thread = Thread.new {
        socket = server.accept
        RSpec::Abq.protocol_read(socket).tap  { socket.close }
      }

      RSpec::Abq.socket

      expect(protocl_version_message_thread.value).to(
        eq(stringify_keys(RSpec::Abq::PROTOCOL_VERSION_MESSAGE))
      )
    end

    it "recognizes if ABQ_SOCKET and ABQ_GENERATE_MANIFEST is set" do
      server = TCPServer.new host, 0
      ENV['ABQ_SOCKET'] = "#{host}:#{server.addr[1]}"
      ENV['ABQ_GENERATE_MANIFEST'] = "1"

      expect(RSpec::Abq::Manifest.should_write_manifest?).to be(true)
      RSpec::Abq::Manifest.write_manifest([])

      socket = server.accept

      expect(RSpec::Abq.protocol_read(socket)).to(
        eq(stringify_keys(RSpec::Abq::PROTOCOL_VERSION_MESSAGE))
      )
      expect(RSpec::Abq.protocol_read(socket)).to(
        eq(stringify_keys(RSpec::Abq::Manifest.generate([])))
      )
    end
  end
end
