require "open3"
require "securerandom"
require "spec_helper"

module ABQQueue
  # starts the queue if it's not started and returns the address
  def self.start!
    @address ||= begin
      stdin_fd, stdout_fd, waiter = Open3.popen2("abq", "start")
      @q = {stdin_fd: stdin_fd, stdout_fd: stdout_fd, waiter: waiter}
      # read queue address
      data = ""
      queue_regex = /(0.0.0.0:\d+)/
      data << stdout_fd.gets until data =~ queue_regex
      data.match(queue_regex)[1]
    end
  end

  def self.address
    start!
  end

  # stops the queue
  def self.stop!
    Process.kill("INT", @q[:waiter].pid)
    @q[:stdout_fd].close
    @q[:stdin_fd].close
    @q[:waiter].value # blocks until the queue is actually stopped
    @q = nil
    @address = nil
  end
end

RSpec.describe "abq test" do
  def abq_test(rspec_command, queue_addr:, run_id:)
    # RWX_ACCESS_TOKEN is set by `captain-cli`.
    # The tests uses a local queue.
    # Here we unset RWX_ACCESS_TOKEN to prevent abq from trying to connect to a remote queue.
    EnvHelper.with_env("RWX_ACCESS_TOKEN" => nil) do
      Open3.popen3("abq", "work", "--queue-addr", queue_addr, "--run-id", run_id) do |_work_stdin_fd, work_stdout_fd, work_stderr_fd, work_thr|
        test_stdout, test_stderr, test_exit_status = Open3.capture3("abq test --queue-addr #{queue_addr} --run-id #{run_id} -- bin/echo_exit_status.rb #{rspec_command}")
        # note: native_runner_exit_status is nil if the manifest wasn't generated
        work_stdout = work_stdout_fd.read

        # bin/echo_exit_status.rb prints the exit status of the native runner
        # this removes it out of the output
        exit_status_regex = /^exit status: (\d+)$\n/
        manifest_generation_exit_status, native_runner_exit_status = work_stdout.scan(exit_status_regex).map(&:first).map(&:to_i)
        worker_stdout_without_native_exit_status = work_stdout.gsub(exit_status_regex, "")

        {
          test: {
            stdout: test_stdout,
            stderr: test_stderr,
            exit_status: test_exit_status
          },
          work: {
            stdout: worker_stdout_without_native_exit_status,
            stderr: work_stderr_fd.read,
            exit_status: work_thr.value
          },
          native_runner_exit_status: {
            manifest: manifest_generation_exit_status,
            runner: native_runner_exit_status
          }
        }
      end
    end
  end

  # remove unstable parts of the output so we can validate that the rest of the test output is stable between runs
  def sanitize_test_output(output)
    sanitize_backtraces(
      output
        .gsub(/\(completed in .+/, "(completed in 0 ms)") # this line is unstable, not just because of timing. Sometimes when a test fails with an exception, the time is ommitted but "completed in" is still inlcluded
        .gsub(/^Finished in \d+\.\d+ seconds \(\d+\.\d+ seconds spent in test code\)$/, "Finished in 0.00 seconds (0.00 seconds spent in test code)") # timing is unstable
        .gsub(/^Starting test run with ID.+/, "Starting test run with ID not-the-real-test-run-id") # and so is the test run id
    )
  end
  alias_method :sanitize_test_error, :sanitize_test_output

  def sanitize_worker_output(output)
    sanitize_backtraces(
      output
        .gsub(/Finished in \d+\.\d+ seconds \(files took \d+\.\d+ seconds to load\)/, "Finished in 0.0 seconds (files took 0.0 seconds to load)") # timing is unstable
    )
  end

  def sanitize_worker_error(output)
    sanitize_backtraces(
      output
        .gsub(/Worker started with id .+/, "Worker started with id not-the-real-test-run-id") # id is unstable
    )
  end

  def sanitize_backtraces(output)
    output
      .gsub(%r{^.+/rspec-abq}, "/rspec-abq") # get rid of prefixes to working directory
      .gsub(/^.+(?:bin|bundler|rubygems|gems).+$\n/, "") # get rid of backtraces outside of rspec-abq
      .gsub(/:\d+:/, ":0:") # get rid of line numbers internally as well to avoid unecessary test churn
  end

  context "with queue and worker" do
    after(:all) do # rubocop:disable RSpec/BeforeAfterAll
      # queue is started by the first test that needs it
      ABQQueue.stop!
    end

    let(:run_id) { SecureRandom.uuid }

    def snapshot_name(example, which_io)
      [example.description.tr(" ", "-"), which_io, File.basename(ENV["BUNDLE_GEMFILE"])].join("-")
    end

    def assert_command_output_consistent(command, example, success:, hard_failure: false, &sanitizers)
      results = abq_test(command, queue_addr: ABQQueue.address, run_id: run_id)

      sanitized = if sanitizers
        sanitizers.call(results.dup)
      else
        results
      end

      aggregate_failures do
        # when there's a hard failure, the manifest generation run's exit status is 1
        expect(results[:native_runner_exit_status][:manifest]).to eq(hard_failure ? 1 : 0)

        expect(sanitize_test_output(sanitized[:test][:stdout])).to match_snapshot(snapshot_name(example, "test-stdout"))
        expect(sanitize_test_error(sanitized[:test][:stderr])).to match_snapshot(snapshot_name(example, "test-stderr"))
        expect(sanitize_worker_output(sanitized[:work][:stdout])).to match_snapshot(snapshot_name(example, "work-stdout"))
        expect(sanitize_worker_error(sanitized[:work][:stderr])).to match_snapshot(snapshot_name(example, "work-stderr"))

        if success
          expect(results[:native_runner_exit_status][:runner]).to eq(0)
          expect(results[:test][:exit_status]).to be_success
          expect(results[:work][:exit_status]).to be_success
        else
          # when there's a hard failure, rspec isn't relaunched after manifest generation
          # so its exit status is simply missing from the output
          expect(results[:native_runner_exit_status][:runner]).to eq(hard_failure ? nil : 1)
          expect(results[:test][:exit_status]).not_to be_success
          expect(results[:test][:exit_status].exitstatus).to eq(1)

          expect(results[:work][:exit_status]).not_to be_success
          # when there's a hard failure, abq has a special exit status to indicate that something went wrong
          expect(results[:work][:exit_status].exitstatus).to eq(hard_failure ? 101 : 1)
        end
      end
      sanitized
    end

    {"failing_specs" => false,
     "successful_specs" => true,
     "pending_specs" => true,
     "raising_specs" => false}.each do |spec_name, spec_passes|
      it "has consistent output for #{spec_name}" do |example|
        assert_command_output_consistent("bundle exec rspec 'spec/fixture_specs/#{spec_name}.rb'", example, success: spec_passes)
      end
    end

    it "has consistent output for specs together" do |example|
      assert_command_output_consistent("bundle exec rspec --pattern 'spec/fixture_specs/*_specs.rb'", example, success: false)
    end

    it "has consistent output for specs together run with rspec-retry", :aggregate_failures do |example|
      EnvHelper.with_env("RSPEC_RETRY_RETRY_COUNT" => "2") do
        expect(
          assert_command_output_consistent(
            "bundle exec rspec --require fixture_specs/rspec_retry_helper --pattern 'spec/fixture_specs/*_specs.rb'", example, success: false
          )[:work][:stdout]
        ).to include("RSpec::Retry: 2nd try") # confirm retry is running (outside of spot checking snapshots)
      end
    end

    # note: this doesn't test rspec-abq's hadnling of random ordering because each worker receives the same seed on the command line
    it "has consistent output for specs together with a hardcoded seed" do |example|
      assert_command_output_consistent("bundle exec rspec --pattern 'spec/fixture_specs/*_specs.rb' --seed 35888", example, success: false)
    end

    context "with random ordering" do
      def sanitize_random_ordering(results)
        dots_regex = /^[.PS]+$/ # note the dot is in a character class so it is implicitly escaped / not a wildcard
        dots = results[:test][:stdout][dots_regex]
        results[:test][:stdout].gsub!(dots_regex, dots.chars.sort.join) # we rewrite the dots to be consistent because otherwise they're random
        results[:work][:stdout] =
          results[:work][:stdout]
            .gsub(/Randomized with seed \d+/, "Randomized with seed this-is-not-random")
            .lines.sort.reject { |line| line.strip == "" }.join # sort lines because tests will not consistently be in order
        results
      end

      # this one _does_ test rspec-abq's handling of random ordering (and because of that isn't a snapshot test :p)
      it "has consistent output for random ordering passed as CLI argument" do |example|
        assert_command_output_consistent("bundle exec rspec spec/fixture_specs/successful_specs.rb spec/fixture_specs/pending_specs.rb --order rand", example, success: true, &method(:sanitize_random_ordering))
      end

      it "has consistent output for random ordering set in rspec config" do |example|
        assert_command_output_consistent("bundle exec rspec spec/fixture_specs/spec_that_sets_up_random_ordering.rb", example, success: true, &method(:sanitize_random_ordering))
      end

      it "has consistent output for random seed set in rspec config" do |example|
        assert_command_output_consistent("bundle exec rspec spec/fixture_specs/spec_that_sets_up_random_seed.rb", example, success: true, &method(:sanitize_random_ordering))
      end
    end

    it "quits early if configured with fail-fast" do |example|
      assert_command_output_consistent("bundle exec rspec spec/fixture_specs/successful_specs.rb spec/fixture_specs/pending_specs.rb --fail-fast", example, success: false, hard_failure: true)
    end

    context "with syntax errors" do
      version = Gem::Version.new(RSpec::Core::Version::STRING)
      # we don't properly fail on syntax errors for versions 3.6, 3.7, and 3.8
      pending_test = version >= Gem::Version.new("3.6.0") && version < Gem::Version.new("3.9.0")
      it "has consistent output for specs with syntax errors" do |example|
        pending("incompatible with rspec 3.6-3.8") if pending_test
        assert_command_output_consistent("bundle exec rspec 'spec/fixture_specs/specs_with_syntax_errors.rb'", example, success: false, hard_failure: true)
      end

      # this one doesn't even pass if pending for 3.6-3.8 so we skip it with metadata
      it "has consistent output for specs together including a syntax error", *[(:skip if pending_test)].compact do |example|
        assert_command_output_consistent("bundle exec rspec --pattern 'spec/fixture_specs/**/*.rb'", example, success: false, hard_failure: true)
      end
    end
  end
end
