require "open3"
require "securerandom"
require "spec_helper"

RSpec.describe "abq test" do
  def abq_test(rspec_command, queue_addr:, run_id:)
    Open3.capture3("abq test --queue-addr #{queue_addr} --run-id #{run_id} -- #{rspec_command}")
  end

  # if test output doesn't exist on disk, write it to a file
  # if it does exist, use the file as the expected output
  def assert_test_output_consistent(matchable_output, test_identifier:)
    expect(matchable_output).to match_snapshot("#{test_identifier}-#{File.basename(ENV["BUNDLE_GEMFILE"])}")
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
    # rubocop:disable RSpec/InstanceVariable
    before(:all) do # rubocop:disable RSpec/BeforeAfterAll
      # start the queue
      @queue_stdin_fd, @queue_stdout_fd, @queue_thr = Open3.popen2("abq", "start")

      # read queue address
      data = ""
      queue_regex = /(0.0.0.0:\d+)\n/
      data << @queue_stdout_fd.gets until data =~ queue_regex
      @queue_addr = data.match(queue_regex)[1]
    end

    after(:all) do # rubocop:disable RSpec/BeforeAfterAll
      # stop the queue
      Process.kill("INT", @queue_thr.pid)
      @queue_stdout_fd.close
      @queue_stdin_fd.close
      @queue_thr.value # blocks until the queue is actually stopped
    end

    around do |example|
      # RWX_ACCESS_TOKEN is set by `captain-cli`.
      # The tests uses a local queue.
      # Here we unset RWX_ACCESS_TOKEN to prevent abq from trying to connect to a remote queue.
      EnvHelper.with_env("RWX_ACCESS_TOKEN" => nil) do
        # start worker
        Open3.popen3("abq", "work", "--queue-addr", @queue_addr, "--run-id", run_id) do |_work_stdin_fd, work_stdout_fd, work_stderr_fd, work_thr|
          @work_stdout_fd = work_stdout_fd
          @work_stderr_fd = work_stderr_fd
          @work_thr = work_thr
          # run the example
          example.run
        end
      end
    end

    let(:run_id) { SecureRandom.uuid }

    def writable_example_id(example)
      example.id[2..].tr("/", "-")
    end

    def assert_command_output_consistent(command, example, success:, worker_status_code: 1, test_stderr_empty: true, &output_sanitizer)
      test_stdout, test_stderr, test_exit_status = abq_test(command, queue_addr: @queue_addr, run_id: run_id)

      writable_example_id = writable_example_id(example)
      work_stdout = @work_stdout_fd.read
      if output_sanitizer
        test_stdout, work_stdout = output_sanitizer.call(test_stdout, work_stdout)
      end

      aggregate_failures do
        assert_test_output_consistent(sanitize_test_output(test_stdout), test_identifier: [writable_example_id, "test-stdout"].join("-"))
        assert_test_output_consistent(sanitize_worker_output(work_stdout), test_identifier: [writable_example_id, "work-stdout"].join("-"))
        assert_test_output_consistent(sanitize_worker_error(@work_stderr_fd.read), test_identifier: [writable_example_id, "work-stderr"].join("-"))

        if test_stderr_empty
          expect(test_stderr).to be_empty
        else
          assert_test_output_consistent(sanitize_test_output(test_stderr), test_identifier: [writable_example_id, "test-stderr"].join("-"))
        end
        worker_exit_status = @work_thr.value
        if success
          expect(test_exit_status).to be_success
          expect(worker_exit_status).to be_success
        else
          expect(test_exit_status).not_to be_success
          expect(test_exit_status.exitstatus).to eq 1
          expect(worker_exit_status).not_to be_success
          expect(worker_exit_status.exitstatus).to eq worker_status_code
        end
      end
    end
    # rubocop:enable RSpec/InstanceVariable

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

    # note: this doesn't test rspec-abq's handling of random ordering because each worker receives the same seed on the command line
    it "has consistent output for specs together with a hardcoded seed" do |example|
      assert_command_output_consistent("bundle exec rspec --pattern 'spec/fixture_specs/*_specs.rb' --seed 35888", example, success: false)
    end

    context "with random ordering" do
      def sanitize_random_stdout(test_stdout, work_stdout)
        dots_regex = /^[.PS]+$/ # note the dot is in a character class so it is implicitly escaped / not a wildcard
        dots = test_stdout[dots_regex]
        sanitized_test_output = test_stdout.gsub(dots_regex, dots.chars.sort.join) # we rewrite the dots to be consistent because otherwise they're random

        sanitized_worker_output = work_stdout.gsub(/Randomized with seed \d+/, "Randomized with seed this-is-not-random") # rubocop:disable RSpec/InstanceVariable
          .lines.sort.reject { |line| line.strip == "" }.join # test the lines because test results are not consistently in the same order
        [sanitized_test_output, sanitized_worker_output]
      end

      # this one _does_ test rspec-abq's handling of random ordering (and because of that isn't a snapshot test :p)
      it "passes on random ordering" do |example| # rubocop:disable RSpec/ExampleLength
        assert_command_output_consistent("bundle exec rspec spec/fixture_specs/successful_specs.rb spec/fixture_specs/pending_specs.rb --order rand", example, success: true, &method(:sanitize_random_stdout))
      end

      it "obeys random ordering if set in spec_helper" do |example|
        assert_command_output_consistent("bundle exec rspec spec/fixture_specs/spec_that_sets_up_random_ordering.rb", example, success: true, &method(:sanitize_random_stdout))
      end
    end

    context "when abq should is expected to fail hard" do
      it "raises an exception if user tries to randomly set the seed" do |example|
        assert_command_output_consistent("bundle exec rspec spec/fixture_specs/spec_that_sets_up_random_seed.rb", example, success: false, worker_status_code: 101, test_stderr_empty: false)
      end

      version = Gem::Version.new(RSpec::Core::Version::STRING)
      # we don't properly fail on syntax errors for versions 3.6, 3.7, and 3.8
      pending_test = version >= Gem::Version.new("3.6.0") && version < Gem::Version.new("3.9.0")
      it "has consistent output for specs with syntax errors" do |example|
        pending if pending_test
        assert_command_output_consistent("bundle exec rspec 'spec/fixture_specs/specs_with_syntax_errors.rb'", example, success: false, worker_status_code: 101, test_stderr_empty: false)
      end

      # this one doesn't even pass if pending for 3.6-3.8 so we skip it with metadata
      it "has consistent output for specs together including a syntax error", *[(:skip if pending_test)].compact do |example|
        assert_command_output_consistent("bundle exec rspec --pattern 'spec/fixture_specs/**/*.rb'", example, success: false, worker_status_code: 101, test_stderr_empty: false)
      end
    end
  end
end
