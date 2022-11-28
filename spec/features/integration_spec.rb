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
      .gsub(/^Starting test run with ID.+/, "Starting test run with ID not-the-real-test-run-id") # and so is the test run id
  end

  def sanitize_worker_output(output)
    output
      .gsub(/Finished in \d+\.\d+ seconds \(files took \d+\.\d+ seconds to load\)/, "Finished in 0.0 seconds (files took 0.0 seconds to load)") # timing is unstable
  end

  def sanitize_worker_error(output)
    output
      .gsub(/Worker started with id .+/, "Worker started with id not-the-real-test-run-id") # timing is unstable
  end

  context "with queue and worker" do
    # rubocop:disable RSpec/InstanceVariable
    before(:all) do # rubocop:disable RSpec/BeforeAfterAll
      # start the queue
      queue_stdin, queue_stdout_fd, @queue_thr = Open3.popen2("abq", "start")
      queue_stdin.close

      # read queue address
      data = ""
      queue_regex = /(0.0.0.0:\d+)\n/
      data << queue_stdout_fd.read(queue_stdout_fd.stat.size) until data =~ queue_regex
      queue_stdout_fd.close
      @queue_addr = data.match(queue_regex)[1]
    end

    after(:all) do # rubocop:disable RSpec/BeforeAfterAll
      # stop the queue
      Process.kill("INT", @queue_thr.pid)
      @queue_thr.value # blocks until the queue is actually stopped
    end

    around do |example|
      # start worker
      Open3.popen3("abq", "work", "--queue-addr", @queue_addr, "--run-id", run_id) do |_work_stdin_fd, work_stdout, work_stderr, work_thr|
        @work_stdout = work_stdout
        @work_stderr = work_stderr
        @work_thr = work_thr
        # run the example
        example.run
      end
    end

    let(:queue_addr) { @queue_addr }
    let(:worker_exit_status) { @work_thr.value }
    let(:worker_output) {
      worker_exit_status # wait for the worker to finish
      @work_stdout.read
    }
    let(:worker_error) {
      worker_exit_status # wait for the worker to finish
      @work_stderr.read
    }
    # rubocop:enable RSpec/InstanceVariable
    let(:run_id) { SecureRandom.uuid }

    it "has consistent output for success", :aggregate_failures do
      test_stdout, test_stderr, test_exit_status = abq_test("bundle exec rspec 'spec/fixture_specs/two_specs.rb'", queue_addr: queue_addr, run_id: run_id)

      expect(test_stderr).to be_empty
      assert_test_output_consistent(sanitize_test_output(test_stdout), test_identifier: "test-stdout-success")
      expect(test_exit_status).to be_success

      assert_test_output_consistent(sanitize_worker_output(worker_output), test_identifier: "work-stdout-success")
      assert_test_output_consistent(sanitize_worker_error(worker_error), test_identifier: "work-stderr-success")
      expect(worker_exit_status).to be_success
    end

    it "has consistent output for failure", :aggregate_failures do
      test_stdout, test_stderr, test_exit_status = abq_test("bundle exec rspec --pattern 'spec/fixture_specs/*_specs.rb'", queue_addr: queue_addr, run_id: run_id)

      expect(test_stderr).to be_empty
      assert_test_output_consistent(sanitize_test_output(test_stdout), test_identifier: "test-stdout-failure")

      assert_test_output_consistent(sanitize_worker_output(worker_output), test_identifier: "work-stdout-failure")
      assert_test_output_consistent(sanitize_worker_error(worker_error), test_identifier: "work-stderr-failure")

      expect(test_exit_status).not_to be_success
      expect(test_exit_status.exitstatus).to eq 1
      expect(worker_exit_status).not_to be_success
      expect(worker_exit_status.exitstatus).to eq 1
    end
  end
end
