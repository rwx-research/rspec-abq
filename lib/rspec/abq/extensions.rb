module RSpec
  module Abq
    # A few extensions to RSpec::Core classes to hook in abq
    module Extensions
      # adds our functionality to RSpec::Core::Configuration
      # @!visibility private
      def self.setup!
        RSpec::Core::ExampleGroup.extend(ExampleGroup)
        RSpec::Core::Runner.prepend(Runner)
        RSpec::Core::World.prepend(World)
      end

      # ExampleGroups are nodes in a tree with
      # - a (potentially empty) list of Examples (the value of the node)
      # - AND a (potentialy empty) list of children ExampleGroups (... the ... children ... are the children of the
      #   node 😅)
      # ExampleGroups are defined by `context` and `describe` in the RSpec DSL
      # Examples are defined dby `it` RSpec DSL
      module ExampleGroup
        # This method
        # - iterates over the current ExampleGroup's Examples to find the Example that is the same as
        #   Abq.target_test_case
        # - runs the example
        # - and fetches example that is now the `Abq.target_test_case`a
        #
        # the next target_test_case is either
        # - later in this ExampleGroup's examples
        #   - so we continue iterating until we get there
        # - or in another ExampleGroup
        #   - so we bail from this iteration and let the caller (run_with_abq) iterate to the right ExampleGroup
        def run_examples_with_abq(reporter)
          all_examples_succeeded = true
          ordering_strategy.order(filtered_examples).each do |considered_example|
            next unless Abq.target_test_case.is_example?(considered_example)
            next if RSpec.world.wants_to_quit

            instance = new(considered_example.inspect_output)
            set_ivars(instance, before_context_ivars)

            # note: it looks like we can inline the next two lines.
            # DON'T DO IT!
            # true &&= expression : expression will be run, fine!
            # false &&= expression: expression will NOT be run! bad!
            # we want to always run the test, even if the previous test failed.
            succeeded = considered_example.run(instance, reporter)
            all_examples_succeeded &&= succeeded

            Abq.fetch_next_example
            break unless Abq.target_test_case.directly_in_group?(self)
          end
          all_examples_succeeded
        end

        # same as .run but using abq
        def run_with_abq(reporter)
          # The next test isn't in this group or any child; we can skip
          # over this group entirely.
          return true unless Abq.target_test_case.in_group?(self)

          reporter.example_group_started(self)

          should_run_context_hooks = descendant_filtered_examples.any?
          begin
            if Gem::Version.new(RSpec::Core::Version::STRING) >= Gem::Version.new("3.11.0")
              RSpec.current_scope = :before_context_hook
            end
            run_before_context_hooks(new("before(:context) hook")) if should_run_context_hooks

            # If the next example to run is on the surface of this group, scan all
            # the examples; otherwise, we just need to check the children groups.
            result_for_this_group =
              if Abq.target_test_case.directly_in_group?(self)
                run_examples_with_abq(reporter)
              else
                true
              end

            results_for_descendants = ordering_strategy.order(children).map { |child| child.run_with_abq(reporter) }.all?
            result_for_this_group && results_for_descendants
          rescue RSpec::Core::Pending::SkipDeclaredInExample => ex
            for_filtered_examples(reporter) do |example|
              if Abq.target_test_case.is_example?(example)
                example.skip_with_exception(reporter, ex)
                Abq.fetch_next_example
              end
            end
            true
          rescue RSpec::Support::AllExceptionsExceptOnesWeMustNotRescue => ex
            # If an exception reaches here, that means we must fail the entire
            # group (otherwise we would have handled the exception locally at an
            # example). Since we know of the examples in the same order as they'll
            # be sent to us from ABQ, we now loop over all the examples, and mark
            # every one that we must run in this group as a failure.
            for_filtered_examples(reporter) do |example|
              if Abq.target_test_case.is_example?(example)
                example.fail_with_exception(reporter, ex)
                Abq.fetch_next_example
              end
            end

            false
          ensure
            if Gem::Version.new(RSpec::Core::Version::STRING) >= Gem::Version.new("3.11.0")
              RSpec.current_scope = :after_context_hook
            end
            run_after_context_hooks(new("after(:context) hook")) if should_run_context_hooks
            reporter.example_group_finished(self)
          end
        end
      end

      # Runner is class responsbile for execution in RSpec
      module Runner
        # Runs the provided example groups.
        #
        # @param example_groups [Array<RSpec::Core::ExampleGroup>] groups to run.
        #   Ignored in favor of @world.ordered_example_groups
        # @return [Fixnum] exit status code. 0 if all specs passed or if rspec-abq wants to quit early,
        #   or the configured failure exit status (1 by default) if specs
        #   failed.
        def run_specs(example_groups)
          if !!ENV[ABQ_GENERATE_MANIFEST]
            # before abq can start workers, it asks for a manifest
            Instrumentation.instrument("run_specs_for_manifest_generation") do
              RSpec::Abq::Manifest.write_manifest(example_groups, RSpec.configuration.seed, RSpec.configuration.ordering_registry)
            end
            # gracefully quit after manifest generation. The worker will launch another instance of rspec with an init_message
            return 0
          end

          return 0 if Abq.fast_exit?

          # if not quitting early, ensure we have an initial test
          Abq.fetch_next_example

          # Note: this is all examples, not the examples run by ABQ. Because of that, the numbers in the worker
          # summary will likely be wrong.
          examples_count = @world.example_count(example_groups)
          examples_passed = @configuration.reporter.report(examples_count) do |reporter|
            @configuration.with_suite_hooks do
              if examples_count == 0 && @configuration.fail_if_no_examples
                return @configuration.failure_exit_code
              end

              example_groups.map { |g| g.run_with_abq(reporter) }.all?
            end
          end

          if Abq.target_test_case != Abq::TestCase.end_marker
            warn "Hit end of test run without being on end marker. Target test case is #{Abq.target_test_case.inspect}"
            examples_passed = false
          end

          if Gem::Version.new(RSpec::Core::Version::STRING) >= Gem::Version.new("3.10.0")
            exit_code(examples_passed)
          else
            examples_passed ? 0 : @configuration.failure_exit_code
          end
        end

        private

        def persist_example_statuses
          if RSpec.configuration.example_status_persistence_file_path
            warn "persisting example status disabled by abq"
          end
        end
      end

      # RSpec uses this for global data that's not configuration
      module World
        # we call configure_rspec in #ordered_example_groups because it is called
        # 1. AFTER all specs are loaded.
        #     We need to call it after all specs are loaded because we want to potentially overwrite config set in the specs
        # 2. BEFORE any specs are run.
        #     We want to call it before any specs are run because the config we set may affect spec ordering.
        def ordered_example_groups
          RSpec::Abq.configure_rspec!
          super
        end
      end
    end
  end
end
