require "set"
module RSpec
  module Abq
    # A module for abstracting ABQ Manifest
    module Manifest
      # writes manifest to abq socket
      def self.write_manifest(ordered_groups, random_seed, registry)
        Abq.protocol_write(generate(ordered_groups, random_seed, registry))
      end

      # Generates an ABQ Manifest
      # @param ordered_groups [Array<RSpec::Core::ExampleGroup>] ordered groups to assemble into a manifest
      def self.generate(ordered_groups, random_seed, registry)
        {
          manifest: {
            init_meta: RSpec::Abq::Ordering.to_meta(random_seed, registry),
            members: ordered_groups.map { |group| to_manifest_group(group) }.compact
          }
        }
      end

      # @visibility private
      # @param group [RSpec::Core::ExampleGroup]
      private_class_method def self.to_manifest_group(group)
        # NB: It's important to write examples first and then children groups,
        # because that's how the runner will execute them.
        members =
          group.ordering_strategy.order(group.filtered_examples).map { |example|
            tags, metadata = Abq.extract_metadata_and_tags(example.metadata)
            {
              type: "test",
              id: example.id,
              tags: tags,
              meta: metadata
            }
          }
            .concat(
              group.ordering_strategy.order(group.children).map { |child_group| to_manifest_group(child_group) }.compact
            )
        return nil if members.empty?
        tags, metadata = Abq.extract_metadata_and_tags(group.metadata)
        {
          type: "group",
          name: group.id,
          tags: tags,
          meta: metadata,
          members: members
        }
      end
    end
  end
end
