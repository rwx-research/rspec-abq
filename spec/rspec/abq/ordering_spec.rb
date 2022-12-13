require "spec_helper"

RSpec.describe RSpec::Abq::Ordering do
  let(:ordering) { RSpec.configuration.ordering_registry.fetch(ordering_name) }
  let(:registry) do
    instance_double(RSpec::Core::Ordering::Registry).tap do |double|
      allow(double).to receive(:fetch) do |name|
        if name == :global
          @ordering ||= ordering
        else
          RSpec.configuration.ordering_registry.fetch(name)
        end
      end

      allow(double).to receive(:register) do |name, ordering|
        if name == :global
          @ordering = ordering
        else
          raise "unsupported"
        end
      end
    end
  end

  let(:seed) { 123 }

  describe ".to_meta(seed, registry)" do
    context "with a :random ordering" do
      let(:ordering_name) do
        :random
      end

      it "writes ordering meta" do
        expect(RSpec::Abq::Ordering.to_meta(seed, registry)).to eq(ordering: :random, seed: seed)
      end
    end

    context "with a :defined ordering" do
      let(:ordering_name) do
        :defined
      end

      it "writes ordering meta" do
        expect(RSpec::Abq::Ordering.to_meta(seed, registry)).to eq(ordering: :defined, seed: seed)
      end
    end

    context "with a :recently_modified ordering" do
      let(:ordering_name) do
        :recently_modified
      end

      if RSpec::Abq::Ordering::SUPPORTED_ORDERINGS.include?(:recently_modified)
        context "when rspec supports it" do
          it "writes ordering meta" do
            expect(RSpec::Abq::Ordering.to_meta(seed, registry)).to eq(ordering: :recently_modified, seed: seed)
          end
        end
      else
        # this test is really here to ensure both legacy and modern tests have the same number of tests to satisfy NUM_TESTS
        # we should remove it when we modify the NUM_TESTS check to be per-gemfile (or if we remove the check)
        context "when rspec doesn't suppor it" do
          let(:ordering) { :recently_modified }

          it "writes ordering meta" do
            expect { RSpec::Abq::Ordering.to_meta(seed, registry) }.to raise_error(RSpec::Abq::Ordering::UnsupportedOrderingError)
          end
        end
      end
    end

    context "with an unsunpported ordering" do
      let(:ordering) do
        :unsupported
      end

      it "raises an exception" do
        expect {
          RSpec::Abq::Ordering.to_meta(123, registry)
        }.to raise_error(RSpec::Abq::Ordering::UnsupportedOrderingError)
      end
    end
  end

  describe ".setup!(init_meta, configuration)" do
    let(:ordering_name) do
      :defined
    end

    let(:configuration) do
      OpenStruct.new(seed: seed, ordering_registry: registry)
    end

    it "does nothing if init_meta settings are identical to configuration", :aggregate_failures do
      init_meta = {"ordering" => "defined", "seed" => seed}
      expect {
        expect(RSpec::Abq::Ordering.setup!(init_meta, configuration)).to be(false)
      }.not_to change { [configuration.seed, configuration.ordering_registry.fetch(:global)] }
    end

    it "sets ordering", :aggregate_failures do
      init_meta = {"ordering" => "random", "seed" => seed}
      expect {
        expect(RSpec::Abq::Ordering.setup!(init_meta, configuration)).to be(true)
      }.to change { [configuration.seed, configuration.ordering_registry.fetch(:global)] }.to([seed, RSpec.configuration.ordering_registry.fetch(:random)])
    end

    it "sets seed", :aggregate_failures do
      init_meta = {"ordering" => "defined", "seed" => seed + 1}
      expect {
        expect(RSpec::Abq::Ordering.setup!(init_meta, configuration)).to be(true)
      }.to change { [configuration.seed, configuration.ordering_registry.fetch(:global)] }.to([seed + 1, RSpec.configuration.ordering_registry.fetch(:defined)])
    end
  end
end
