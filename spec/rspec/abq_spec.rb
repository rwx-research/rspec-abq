require "socket"
require "spec_helper"

def stringify_keys(hash)
  hash.map { |k, v| [k.to_s, v.is_a?(Hash) ? stringify_keys(v) : v] }.to_h
end

RSpec.describe RSpec::Abq do
  describe ".configure_rspec!", unless: RSpec::Abq.disable_tests_when_run_by_abq? do
    let(:init_message) { {init_meta: {seed: 124, ordering: "defined"}} }
    let(:configuration_double) do
      instance_double(
        RSpec::Core::Configuration,
        {
          :fail_fast => false,
          :dry_run? => false,
          :example_status_persistence_file_path= => nil,
          :add_formatter => nil
        }.merge(
          if Gem::Version.new(RSpec::Core::Version::STRING) >= Gem::Version.new("3.6.0")
            {:color_mode= => nil}
          else
            {:color= => nil}
          end
        )
      )
    end

    before do
      # stub out socket communication
      allow(RSpec::Abq).to receive(:protocol_read).and_return(stringify_keys(init_message))
      allow(RSpec::Abq).to receive(:protocol_write)

      RSpec::Abq.instance_variable_set(:@fast_exit, false)
      RSpec::Abq.instance_variable_set(:@rspec_configured, false)

      # don't execute the ordering setup -- it's tested in integrations
      allow(RSpec::Abq::Ordering).to receive(:setup!)

      # don't modify the current rspec instance's rspec config
      allow(RSpec).to receive(:configuration).and_return(configuration_double)
    end

    context 'with the ABQ_GENERATE_MANIFEST env var set to "true"' do
      around { |example| EnvHelper.with_env(RSpec::Abq::ABQ_GENERATE_MANIFEST => "true") { example.run } }

      it "if the manifest env var is set, it bails before initialization" do
        expect(RSpec::Abq).not_to receive(:protocol_read)
        RSpec::Abq.configure_rspec!
      end
    end

    it "if the manifest env var isn't set, it initializes" do # rubocop:disable RSpec/MultipleExpectations
      expect(RSpec::Abq).to receive(:protocol_read)
      expect(RSpec).to receive(:configuration)
      RSpec::Abq.configure_rspec!
    end

    context "when the init message asks to fast exit" do
      let(:init_message) { {fast_exit: true} }

      it "abq knows to fast exit", :aggregate_failures do
        expect(RSpec::Abq::Ordering).not_to receive(:setup)
        RSpec::Abq.configure_rspec!

        expect(RSpec::Abq).to be_fast_exit
      end
    end

    context "when the init message is not empty" do
      it "sets up ordering", :aggregate_failures do
        expect(RSpec::Abq::Ordering).to receive(:setup!).with(stringify_keys(init_message[:init_meta]), configuration_double)

        RSpec::Abq.configure_rspec!
        expect(RSpec::Abq).not_to be_fast_exit
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

  describe ".check_configuration!(config)" do
    it "does nothing if fail_fast is nil" do
      expect {
        RSpec::Abq.check_configuration!(instance_double(RSpec::Core::Configuration, fail_fast: nil))
      }.not_to raise_error
    end

    it "raises if fail_fast is set" do
      expect {
        RSpec::Abq.check_configuration!(instance_double(RSpec::Core::Configuration, fail_fast: true))
      }.to raise_error(RSpec::Abq::UnsupportedConfigurationError)
    end
  end

  describe RSpec::Abq::Manifest do
    # more manifest tests in features/manifest_spec.rb
    describe ".write_manifest(example_groups)" do
      it "writes manifest over socket" do
        allow(RSpec::Abq).to receive(:protocol_write)
        registry = RSpec.configuration.ordering_registry
        expect(RSpec::Abq).to receive(:protocol_write).with(RSpec::Abq::Manifest.generate([], 1, registry))
        RSpec::Abq::Manifest.write_manifest([], 1, registry)
      end
    end
  end
end
