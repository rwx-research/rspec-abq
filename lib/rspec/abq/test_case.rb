module RSpec
  module Abq
    # ABQ's representation of a test case
    class TestCase
      def initialize(id, tags, meta)
        @id = id
        @tags = tags
        @meta = meta
        @rerun_file_path, scoped_id = RSpec::Core::Example.parse_id @id
        @scope = self.class.parse_scope(scoped_id || "")
      end

      attr_reader :id
      attr_reader :tags
      attr_reader :meta
      attr_reader :rerun_file_path
      attr_reader :scoped_id

      # Parses a scope n:m:q:r into [n, m, q, r]
      # Invariant of RSpec is that a scope n:m:q:r is contained in a scope n:m:q
      def self.parse_scope(scope)
        scope.split(":")
      end

      # `scope_contains outer inner` is true iff the inner scope is deeper
      # than the outer scope.
      #
      # @param outer [Array<String>] parsed scope
      # @param inner [Array<String>] parsed scope
      def self.scope_contains(outer, inner)
        inner.take(outer.length) == outer
      end

      # `scope_leftover outer inner` returns the partial scopes of `inner`
      # that are deeper than `outer`.
      #
      # @param outer [Array<String>] parsed scope
      # @param inner [Array<String>] parsed scope
      def self.scope_leftover(outer, inner)
        inner[outer.length..-1] || []
      end

      # @param group [RSpec::Core::ExampleGroup]
      def in_group?(group)
        return false if group.metadata[:rerun_file_path] != @rerun_file_path

        group_scope = self.class.parse_scope(group.metadata[:scoped_id])
        self.class.scope_contains(group_scope, @scope)
      end

      # @param group [RSpec::Core::ExampleGroup]
      def directly_in_group?(group)
        return false unless in_group?(group)

        group_scope = self.class.parse_scope(group.metadata[:scoped_id])
        additional_scoping = self.class.scope_leftover(group_scope, @scope)
        raise "#{@id} not inside #{group_scope}, but we thought it was" if additional_scoping.empty?
        additional_scoping.length == 1
      end

      # @param example [RSpec::Core::Example]
      def is_example?(example)
        example.metadata[:rerun_file_path] == @rerun_file_path && self.class.parse_scope(example.metadata[:scoped_id]) == @scope
      end

      # Faux test case to mark end of all tests. Will never match any group or
      # test ID, since the scoped_id is empty.
      def self.end_marker
        @end_marker ||= TestCase.new("[]", [], {})
      end

      # stringify but mostly used for debugging
      def to_s
        "Test case id: #{id}, tags: #{tags}, meta: #{meta}"
      end
    end
  end
end
