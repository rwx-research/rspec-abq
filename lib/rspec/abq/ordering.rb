module RSpec
  module Abq
    module Ordering
      SUPPORTED_ORDERINGS = [:defined, :recently_modified, :random]
      UnsupportedOrderingError = Class.new(StandardError)

      def self.to_meta(seed, registry)
        global_ordering = registry.fetch(:global)
        ordering_name = SUPPORTED_ORDERINGS.find { |name| registry.fetch(name) == global_ordering }
        fail(UnsupportedOrderingError, "can't order based on unknown ordering: `#{global_ordering.class}`") unless ordering_name
        {
          ordering: ordering_name,
          seed: seed
        }
      end

      def self.setup!(init_meta, configuration)
        configuration.seed = init_meta["seed"]
        registry = configuration.ordering_registry
        ordering_from_manifest = registry.fetch(init_meta["ordering"].to_sym) do
          fail(UnsupportedOrderingError, "can't order based on unknown ordering: `#{init_meta["ordering"]}`")
        end
        registry.register(:global, ordering_from_manifest)
      end
    end
  end
end
