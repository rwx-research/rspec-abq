module RSpec
  module Abq
    # This module is responsible for recording ordering for the manifest
    # and reading the ordering from `init_meta` to set up the current processes settings
    module Ordering
      # notably: we don't support custom orderings
      SUPPORTED_ORDERINGS =
        if Gem::Version.new(RSpec::Core::Version::STRING) >= Gem::Version.new("3.11.0")
          [:defined, :recently_modified, :random]
        else
          [:defined, :random]
        end

      # Raised when we experience an ordering that doesn't exist in SUPPORTED_ORDERINGS
      UnsupportedOrderingError = Class.new(StandardError)

      # takes a seed and a registry and produces a hash for the manifest
      def self.to_meta(seed, registry)
        global_ordering = registry.fetch(:global)
        ordering_name = SUPPORTED_ORDERINGS.find { |name| registry.fetch(name) == global_ordering }
        fail(UnsupportedOrderingError, "can't order based on unknown ordering: `#{global_ordering.class}`") unless ordering_name
        {
          ordering: ordering_name,
          seed: seed
        }
      end

      # takes the meta (prodced in .to_meta) and applies the settings to the current process
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
