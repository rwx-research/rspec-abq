require "open3"
require "spec_helper"

RSpec.describe "abq test" do # rubocop:disable RSpec/DescribeClass
  def abq_test(rspec_command, queue_addr: nil, run_id: nil)
    args = ["abq", "test"]

    if queue_addr
      args << "--queue-addr" << queue_addr
    end

    if run_id
      args << "--run-id" << run_id
    end

    args << "--" << rspec_command

    command = args.join(" ")
    warn "Running: #{command}"
    Open3.capture3(command)
  end

  def write_or_match(test_identifier, matchable_output)
    file_path = "abq_spec/test-outputs/#{test_identifier}-#{File.basename(ENV["BUNDLE_GEMFILE"])}.txt"
    if !File.exist?(file_path) || ENV["UPDATE_SNAPSHOTS"]
      File.write(file_path, matchable_output)
    else
      expect(matchable_output).to eq(File.read(file_path))
    end
  end

  def sanitize_output(output)
    output.gsub(/completed in \d+ ms/, "completed in 0 ms").gsub(/^Starting test run with ID.+\n/, "")
  end

  def worker_output_looks_good(stderr)
    expect(stderr.lines).to all(match(/warning: |(?:^Worker started)/))
  end

  QUEUE_REGEX = /(0.0.0.0:\d+)\n/
  context "with queue and worker" do
    around do |example|
      # start the queue
      Open3.popen2("abq", "start") do |_queue_stdin, queue_stdout_fd, queue_thr|
        # read queue address
        data = ""
        data << queue_stdout_fd.read(queue_stdout_fd.stat.size) until data =~ QUEUE_REGEX
        @queue_addr = data.match(QUEUE_REGEX)[1]

        # start worker
        @run_id = "test-run-id"
        Open3.popen2e("abq", "work", "--queue-addr", @queue_addr, "--run-id", @run_id) do |_work_stdin_fd, work_stdout_and_stderr_fd, work_thr|
          @work_stdout_and_stderr_fd = work_stdout_and_stderr_fd
          @work_thr = work_thr
          # run the example
          example.call
        end
        # stop the queue
        Process.kill("INT", queue_thr.pid)
      end
    end

    let(:worker_output) { @work_stdout_and_stderr_fd.read(@work_stdout_and_stderr_fd.stat.size) }
    let(:worker_exit_status) { @work_thr.value.exitstatus }

    it "has consistent output for success", aggregate_failures: true do
      test_stdout, _test_stderr, test_status = abq_test("bundle exec rspec --out /dev/null 'spec/fixture_specs/two_specs.rb'", queue_addr: @queue_addr, run_id: @run_id)
      write_or_match("success", sanitize_output(test_stdout))
      expect(test_status.exitstatus).to eq(0)
      worker_output_looks_good(worker_output)
      expect(worker_exit_status).to eq(0)
    end

    it "has consistent output for failure", aggregate_failures: true do
      test_stdout, _test_stderr, test_status = abq_test("bundle exec rspec --out /dev/null --pattern 'spec/fixture_specs/*_specs.rb'", queue_addr: @queue_addr, run_id: @run_id)
      write_or_match("failure", sanitize_output(test_stdout))
      worker_output_looks_good(worker_output)
      expect(test_status.exitstatus).to eq(1)
      expect(worker_exit_status).to eq(1)
    end
  end
end
