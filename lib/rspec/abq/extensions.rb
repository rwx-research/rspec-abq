module RSpec
  module Abq
    module Extensions
      module ExampleGroup
        # @private
        # ExampleGroups are nodes in a tree with
        # - a (potentially empty) list of Examples (the value of the node)
        # - AND a (potentialy empty) list of children ExampleGroups (... the ... children ... are the children of the
        #   node 😅)
        # ExampleGroups are defined by `context` and `describe` in the RSpec DSL
        # Examples are defined dby `it` RSpec DSL
        #
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
        def run_examples_with_abq
          all_examples_succeeded = true
          ordering_strategy.order(filtered_examples).each do |considered_example|
            next unless Abq.target_test_case.is_example?(considered_example)
            next if RSpec.world.wants_to_quit

            instance = new(considered_example.inspect_output)
            set_ivars(instance, before_context_ivars)

            all_examples_succeeded &&= Abq.send_test_result_and_advance { |abq_reporter| considered_example.run(instance, abq_reporter) }

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
            RSpec.current_scope = :before_context_hook
            run_before_context_hooks(new("before(:context) hook")) if should_run_context_hooks

            # If the next example to run is on the surface of this group, scan all
            # the examples; otherwise, we just need to check the children groups.
            result_for_this_group =
              if Abq.target_test_case.directly_in_group? self
                run_examples_with_abq
              else
                true
              end

            results_for_descendants = ordering_strategy.order(children).map { |child| child.run_with_abq(reporter) }.all?
            result_for_this_group && results_for_descendants
          rescue Pending::SkipDeclaredInExample => ex
            for_filtered_examples(reporter) { |example| example.skip_with_exception(reporter, ex) }
            true
          rescue Support::AllExceptionsExceptOnesWeMustNotRescue => ex
            # If an exception reaches here, that means we must fail the entire
            # group (otherwise we would have handled the exception locally at an
            # example). Since we know of the examples in the same order as they'll
            # be sent to us from ABQ, we now loop over all the examples, and mark
            # every one that we must run in this group as a failure.
            for_filtered_examples(reporter) do |example|
              next unless Abq.target_test_case.is_example? example

              Abq.send_test_result_and_advance { |abq_reporter| example.fail_with_exception(abq_reporter, ex) }
            end

            RSpec.world.wants_to_quit = true if reporter.fail_fast_limit_met?
            false
          ensure
            RSpec.current_scope = :after_context_hook
            run_after_context_hooks(new("after(:context) hook")) if should_run_context_hooks
            reporter.example_group_finished(self)
          end
        end
      end

      module Runner
        # Runs the provided example groups.
        #
        # @param example_groups [Array<RSpec::Core::ExampleGroup>] groups to run
        # @return [Fixnum] exit status code. 0 if all specs passed,
        #   or the configured failure exit code (1 by default) if specs
        #   failed.
        def run_specs(example_groups)
          RSpec::Abq.setup_after_specs_loaded!
          return if RSpec.world.wants_to_quit
          examples_count = @world.example_count(example_groups)
          examples_passed = @configuration.reporter.report(examples_count) do |reporter|
            @configuration.with_suite_hooks do
              if examples_count == 0 && @configuration.fail_if_no_examples
                return @configuration.failure_exit_code
              end

              example_groups.map { |g| g.run_with_abq(reporter) }.all?
            end
          end

          exit_code(examples_passed)
        end

        private

        def persist_example_statuses
          if RSpec.configuration.example_status_persistence_file_path
            warn "persisting example status disabled by abq"
          end
        end
      end
    end
  end
end
