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
    file_path = "spec/test-outputs/#{test_identifier}-#{File.basename(ENV["BUNDLE_GEMFILE"])}.txt"
    if !File.exist?(file_path) || ENV["UPDATE_SNAPSHOTS"]
      File.write(file_path, matchable_output)
    else
      expect(matchable_output).to eq(File.read(file_path))
    end
  end

  # remove unstable parts of the output so we can validate that the rest of the test output is stable between runs
  def sanitize_test_output(output)
    output
      .gsub(/completed in \d+ ms/, "completed in 0 ms") # timing is unstable
      .gsub(/^Finished in .* seconds .*$/, "Finished in 0 seconds") # timing is unstable
      .gsub(/^Starting test run with ID.+/, "Starting test run with ID not-the-real-test-run-id") # and so is the test run id
  end

  def sanitize_worker_output(output)
    sanitize_backtraces(
      output
        .gsub(/Finished in \d+\.\d+ seconds \(files took \d+\.\d+ seconds to load\)/, "Finished in 0.0 seconds (files took 0.0 seconds to load)") # timing is unstable
    )
  end

  def sanitize_backtraces(output)
    output.gsub(%r{.+(bundler|rspec-abq|rubygems|gems)/}, '/\1/')
  end

  def sanitize_worker_error(output)
    sanitize_backtraces(
      output
        .gsub(/Worker started with id .+/, "Worker started with id not-the-real-test-run-id") # timing is unstable
        .gsub(/^.*lib\/rspec\/core.*: warning.*$/, "") # strip file path warnings
        .gsub(%r{.+(bundler|rspec-abq|rubygems|gems)/}, '/\1/')
    )
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
      # start worker
      Open3.popen3("abq", "work", "--queue-addr", @queue_addr, "--run-id", run_id) do |_work_stdin_fd, work_stdout_fd, work_stderr_fd, work_thr|
        @work_stdout_fd = work_stdout_fd
        @work_stderr_fd = work_stderr_fd
        @work_thr = work_thr
        # run the example
        example.run
      end
    end

    let(:run_id) { SecureRandom.uuid }

    def assert_worker_output_consistent(command, example, success:, worker_status_code: 1, test_stderr_empty: true)
      test_stdout, test_stderr, test_exit_status = abq_test(command, queue_addr: @queue_addr, run_id: run_id)

      writable_example_id = example.id[2..].tr("/", "-")
      assert_test_output_consistent(sanitize_test_output(test_stdout), test_identifier: [writable_example_id, "test-stdout"].join("-"))
      assert_test_output_consistent(sanitize_worker_output(@work_stdout_fd.read), test_identifier: [writable_example_id, "work-stdout"].join("-"))
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
    # rubocop:enable RSpec/InstanceVariable

    {"failing_specs" => false,
     "successful_specs" => true,
     "pending_specs" => true,
     "raising_specs" => false}.each do |spec_name, spec_passes|
      it "has consistent output for #{spec_name}", :aggregate_failures do |example|
        assert_worker_output_consistent("bundle exec rspec 'spec/fixture_specs/#{spec_name}.rb'", example, success: spec_passes)
      end
    end

    it "has consistent output for specs together", :aggregate_failures do |example|
      assert_worker_output_consistent("bundle exec rspec --pattern 'spec/fixture_specs/*_specs.rb'", example, success: false)
    end

    it "has consistent output for specs with syntax errors", :aggregate_failures do |example|
      assert_worker_output_consistent("bundle exec rspec 'spec/fixture_specs/specs_with_syntax_errors.rb'", example, success: false, worker_status_code: 101, test_stderr_empty: false)
    end

    it "has consistent output for specs together including a syntax error", :aggregate_failures do |example|
      assert_worker_output_consistent("bundle exec rspec --pattern 'spec/fixture_specs/**/*.rb'", example, success: false, worker_status_code: 101, test_stderr_empty: false)
    end
  end
end
