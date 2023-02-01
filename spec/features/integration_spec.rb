require "fileutils"
require "json"
require "open3"
require "securerandom"
require "spec_helper"

module AbqQueue
  # starts the queue if it's not started and returns the address
  def self.start!
    @address ||= begin
      stdin_fd, stdout_fd, waiter = Open3.popen2("abq", "start")
      @q = {stdin_fd: stdin_fd, stdout_fd: stdout_fd, waiter: waiter}
      # read queue address
      data = ""
      queue_regexp = /(0.0.0.0:\d+)/
      data << stdout_fd.gets until data =~ queue_regexp
      data.match(queue_regexp)[1]
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

  def self.output_directory
    @output_directory ||= "tmp/test-results-#{(Time.now.to_f * 1000).to_i}".tap do |path|
      FileUtils.mkdir_p(path)
    end
  end
end

class AbqTestRun
  Output = Struct.new(:exit_status, :stdout, :stderr) do
    def self.default
      @default ||= new(999, "", "")
    end
  end

  attr_reader :manifest_generation_exit_status, :native_runner_exit_status, :results_path

  def initialize(rspec_command, queue_address:, run_id:)
    @rspec_command = rspec_command
    @queue_address = queue_address
    @run_id = run_id
    @results_path = File.join(AbqQueue.output_directory, "#{run_id}.json")
  end

  def results
    @results ||=
      if File.exist?(@results_path)
        JSON.parse(File.read(@results_path))
      end
  end

  def test_output
    @test_output || Output.default
  end

  def run
    raise "#{self.class} cannot be run more than once" if @ran
    @ran = true

    test_stdout, test_stderr, test_exit_status = Open3.capture3(
      "abq test --worker 0 --queue-addr #{@queue_address} --run-id #{@run_id} --reporter dot --reporter rwx-v1-json=#{@results_path} -- bin/echo_exit_status.rb #{@rspec_command}"
    )

    # bin/echo_exit_status.rb prints the exit status of the native runner
    # this removes it out of the output
    exit_status_regexp = /^exit status: (\d+)$\n/
    @manifest_generation_exit_status, @native_runner_exit_status = test_stdout.scan(exit_status_regexp).map(&:first).map(&:to_i)

    @test_output = Output.new(test_exit_status.exitstatus, test_stdout, test_stderr)
  end
end

RSpec.describe "abq test" do
  def abq_test(rspec_command, queue_address:, run_id:)
    # RWX_ACCESS_TOKEN is set by `captain-cli`.
    # The tests uses a local queue.
    # Here we unset RWX_ACCESS_TOKEN to prevent abq from trying to connect to a remote queue.
    EnvHelper.with_env("RWX_ACCESS_TOKEN" => nil) do
      AbqTestRun.new(rspec_command, queue_address: queue_address, run_id: run_id).tap(&:run)
    end
  end

  def sorted_dots(output)
    dots_regexp = /^[.EFPS]+$/ # note the dot is in a character class so it is implicitly escaped / not a wildcard
    matched_dots = output[dots_regexp]
    return output unless matched_dots

    # we rewrite the dots to be consistent because otherwise they're random
    output.gsub(dots_regexp, matched_dots.chars.sort.join)
  end

  def replace_worker_ids(output)
    uuid_regexp = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
    worker_regexp = /--- \[worker (#{uuid_regexp.source})\]|; worker \[(#{uuid_regexp.source})\]|started on worker (#{uuid_regexp.source})/
    worker_ids = output.scan(worker_regexp).flatten.uniq.compact
    return output if worker_ids.empty?

    output.gsub(Regexp.union(*worker_ids), "not-a-real-worker-id")
  end

  # remove unstable parts of the output so we can validate that the rest of the test output is stable between runs
  def sanitize_output(output)
    output = sorted_dots(output)
    output = replace_worker_ids(output)
    output = sanitize_backtrace(output)
    output = sanitize_ruby_version_deprecations(output)
    output
      .gsub(run_id, "not-the-real-test-run-id") # id is not stable
      .gsub(/^Finished in \d+\.\d+ seconds \(\d+\.\d+ seconds spent in test code\)$/, "Finished in 0.00 seconds (0.00 seconds spent in test code)") # timing is unstable
      .gsub(/^Finished in \d+(?:\.\d+)? second(?:s)? \(files took \d+(?:\.\d+)? second(?:s)? to load\)$/, "Finished in 0.0 seconds (files took 0.0 seconds to load)") # timing is unstable
      .gsub(/\(completed in .*; worker/, "(completed in 0 ms; worker") # this line is unstable, not just because of timing. Sometimes when a test fails with an exception, the time is ommitted but "completed in" is still inlcluded
      .gsub(/^Randomized with seed \d+/, "Randomized with seed not-a-real-seed")
      .gsub(/^$\n/, "")
      .strip
  end

  def sanitize_backtrace(output)
    output
      .gsub(%r{^.+/rspec-abq}, "/rspec-abq") # get rid of prefixes to working directory
      .gsub(%r{\\n.+/rspec-abq}, "/rspec-abq") # get rid of prefixes to working directory in escaped strings
      .gsub(%r{^\s+# [^\s]+/(?:bin|bundler|rubygems|gems)/.+$\n}, "") # get rid of backtraces outside of rspec-abq
      .gsub(%r{^\s*"[^\s]+/(?:bin|bundler|rubygems|gems)/.+",?$}, "") # get rid of backtraces outside of rspec-abq in pretty JSON
      .gsub(%r{\\n\s+# [^\s]+/(?:bin|bundler|rubygems|gems)/.+\\n}, "") # get rid of backtraces outside of rspec-abq in escaped strings
      .gsub(/\.rb:\d+/, ".rb:0") # get rid of line numbers to avoid unecessary test churn
  end

  def sanitize_ruby_version_deprecations(output)
    replacers = [
      "warning: Passing safe_level with the 2nd argument of ERB.new is deprecated. Do not use it, and specify other arguments as keyword arguments.",
      "warning: Passing trim_mode with the 3rd argument of ERB.new is deprecated. Use keyword argument like ERB.new(str, trim_mode: ...) instead."
    ].map do |message|
      /[^\s]+:0: #{Regexp.escape(message)}/
    end

    output.gsub(Regexp.union(replacers), "")
  end

  def deep_sort_hash_keys(hash)
    hash.each do |key, value|
      case value
      when Hash
        hash[key] = deep_sort_hash_keys(value)
      when Array
        hash[key] = value.map { |elem| elem.is_a?(Hash) ? deep_sort_hash_keys(elem) : elem }
      end
    end

    hash.sort.to_h
  end

  def sanitize_test_results(results)
    sanitized_text = sanitize_output(JSON.pretty_generate(results)) # sanitize line numbers, etc.
    results = begin
      JSON.parse(sanitized_text)
    rescue JSON::ParserError => e
      RSpec.configuration.reporter.message(
        "Error parsing sanitized output:\n#{e.message}\n\nSanitized output:\n#{sanitized_text}\n\nOriginal results:\n#{JSON.pretty_generate(results)}"
      )
    end

    results["tests"] = results["tests"].sort_by { |t| t["name"] }
    results["tests"] = results["tests"].map do |test|
      test.fetch("attempt").merge!(
        "durationInNanoseconds" => 234_000,
        "startedAt" => "2023-01-01T00:00:00Z",
        "finishedAt" => "2023-01-01T00:00:00Z",
        # Output is shifting; try to remove this in a follow-up.
        "stderr" => "redacted",
        "stdout" => "redacted"
      )

      test.fetch("location")["line"] = 299

      attempt = test.fetch("attempt")
      if attempt.key?("status")
        status = attempt["status"]
        status["message"] = sanitize_backtrace(status["message"]) if status["message"]
        if status["backtrace"]
          status["backtrace"] = status["backtrace"].map { |line| sanitize_backtrace(line).strip }.reject(&:empty?)
        end
      end

      screenshot = test.fetch("attempt").fetch("meta", {})["screenshot"]
      if screenshot
        screenshot["html"] = "tmp/screenshot.html" if screenshot["html"]
        screenshot["image"] = "tmp/screenshot.png" if screenshot["image"]
      end
      test
    end

    deep_sort_hash_keys(results)
  end

  def formatted_test_result_output(run_results)
    JSON.pretty_generate(sanitize_test_results(run_results))
  end

  context "with queue and worker", :aggregate_failures do
    after(:all) do # rubocop:disable RSpec/BeforeAfterAll
      # queue is started by the first test that needs it
      AbqQueue.stop!
    end

    let(:run_id) { SecureRandom.uuid }

    def snapshot_name(example, which_io)
      [example.description.tr(" ", "-"), which_io, File.basename(ENV["BUNDLE_GEMFILE"])].join("-")
    end

    def summary_counts(tests: 0, successful: 0, failed: 0, pended: 0, skipped: 0, retries: 0, quarantined: 0, canceled: 0, timed_out: 0, other_errors: 0, todo: 0)
      {
        "tests" => tests,
        "successful" => successful,
        "failed" => failed,
        "pended" => pended,
        "skipped" => skipped,
        "retries" => retries,
        "quarantined" => quarantined,
        "canceled" => canceled,
        "timedOut" => timed_out,
        "otherErrors" => other_errors,
        "todo" => todo
      }
    end

    it "reports all specs together" do # rubocop:disable RSpec/ExampleLength
      run = abq_test("bundle exec rspec --pattern 'spec/fixture_specs/*_specs.rb'", queue_address: AbqQueue.address, run_id: run_id)

      summary = run.results.fetch("summary")
      expect(summary.fetch("status")["kind"]).to eq("failed")
      expect(summary).to include(summary_counts(tests: 15, successful: 1, failed: 5, pended: 3, skipped: 6))
      expect(run.results["tests"].count).to eq(15)
      expect(sorted_dots(run.test_output.stdout)).to match(/^\.EEEEFPPPSSSSSS$/)
      expect(run.manifest_generation_exit_status).to eq(0)
      expect(run.native_runner_exit_status).to eq(1)
      expect(run.test_output.exit_status).to eq(1)
      expect(run.test_output.stdout).not_to include("Randomized with seed")
    end

    it "has consistent output" do |example|
      # --options /dev/null prevents rspec from loading `.rspec` (which sets the formatter)
      # This minimizes our stdout output captured in the snapshot to just enough that
      # gives us confidence messages are being captured by the test supervisor.
      run = abq_test(
        "bundle exec rspec --options /dev/null --out /dev/null --pattern 'spec/fixture_specs/*_specs.rb'",
        queue_address: AbqQueue.address,
        run_id: run_id
      )

      expect(formatted_test_result_output(run.results)).to match_snapshot(snapshot_name(example, "test-results"))
      # Disable validation of stdout/stderr until we can keep these consistent.
      # expect(sanitize_output(run.test_output.stdout)).to match_snapshot(snapshot_name(example, "test-stdout"))
      # expect(sanitize_output(run.test_output.stderr)).to match_snapshot(snapshot_name(example, "test-sterr"))
    end

    it "reports successful specs" do
      run = abq_test("bundle exec rspec 'spec/fixture_specs/successful_specs.rb'", queue_address: AbqQueue.address, run_id: run_id)

      summary = run.results.fetch("summary")
      expect(summary.fetch("status")["kind"]).to eq("successful")
      expect(summary).to include(summary_counts(tests: 1, successful: 1))
      expect(sorted_dots(run.test_output.stdout)).to match(/^\.$/)
      expect(run.manifest_generation_exit_status).to eq(0)
      expect(run.native_runner_exit_status).to eq(0)
      expect(run.test_output.exit_status).to eq(0)
    end

    it "reports failed specs" do
      run = abq_test("bundle exec rspec 'spec/fixture_specs/failing_specs.rb'", queue_address: AbqQueue.address, run_id: run_id)

      summary = run.results.fetch("summary")
      expect(summary.fetch("status")["kind"]).to eq("failed")
      expect(summary).to include(summary_counts(tests: 2, failed: 2))
      expect(sorted_dots(run.test_output.stdout)).to match(/^EF$/)
    end

    it "reports pended specs" do
      run = abq_test("bundle exec rspec 'spec/fixture_specs/pending_specs.rb'", queue_address: AbqQueue.address, run_id: run_id)

      summary = run.results.fetch("summary")
      expect(summary.fetch("status")["kind"]).to eq("successful")
      expect(summary).to include(summary_counts(tests: 3, pended: 3, skipped: 0))
      expect(sorted_dots(run.test_output.stdout)).to match(/^PPP$/)
    end

    it "reports skipped specs" do
      run = abq_test("bundle exec rspec 'spec/fixture_specs/skipped_specs.rb'", queue_address: AbqQueue.address, run_id: run_id)

      summary = run.results.fetch("summary")
      expect(summary.fetch("status")["kind"]).to eq("successful")
      expect(summary).to include(summary_counts(tests: 6, pended: 0, skipped: 6))
      expect(sorted_dots(run.test_output.stdout)).to match(/^SSSSSS$/)
    end

    it "reports raising specs" do
      run = abq_test("bundle exec rspec 'spec/fixture_specs/raising_specs.rb'", queue_address: AbqQueue.address, run_id: run_id)

      summary = run.results.fetch("summary")
      expect(summary.fetch("status")["kind"]).to eq("failed")
      expect(summary).to include(summary_counts(tests: 3, failed: 3))
      expect(sorted_dots(run.test_output.stdout)).to match(/^EEE$/)
    end

    it "has consistent output with rspec-retry" do |example|
      EnvHelper.with_env("RSPEC_RETRY_RETRY_COUNT" => "2") do
        run = abq_test("bundle exec rspec --require fixture_specs/rspec_retry_helper --pattern 'spec/fixture_specs/*_specs.rb'", queue_address: AbqQueue.address, run_id: run_id)

        # rspec-retry outputs the ordinalized attempt number on each attempt
        expect(run.test_output.stdout).to include("RSpec::Retry: 2nd try")

        summary = run.results.fetch("summary")
        expect(summary.fetch("status")["kind"]).to eq("failed")
        # rspec-retry doesn't include attempt information in results
        expect(summary).to include(summary_counts(tests: 15, successful: 1, failed: 5, pended: 3, skipped: 6))
        expect(run.results["tests"].count).to eq(15)
        expect(formatted_test_result_output(run.results)).to match_snapshot(snapshot_name(example, "test-results"))
      end
    end

    it "has consistent output with capybara" do |example|
      run = abq_test("bundle exec rspec spec/fixture_specs/spec_with_capybara.rb", queue_address: AbqQueue.address, run_id: run_id)

      summary = run.results.fetch("summary")
      expect(summary.fetch("status")["kind"]).to eq("failed")
      expect(summary).to include(summary_counts(tests: 2, successful: 1, failed: 1))
      expect(sorted_dots(run.test_output.stdout)).to match(/^\.F$/)
      expect(formatted_test_result_output(run.results)).to match_snapshot(snapshot_name(example, "test-results"))
    end

    # note: this doesn't test rspec-abq's handling of random ordering because each worker receives the same seed on the command line
    it "has consistent output for specs together with a hardcoded seed" do |example|
      run = abq_test("bundle exec rspec --pattern 'spec/fixture_specs/*_specs.rb' --seed 35888", queue_address: AbqQueue.address, run_id: run_id)

      summary = run.results.fetch("summary")
      expect(summary.fetch("status")["kind"]).to eq("failed")
      expect(summary).to include(summary_counts(tests: 15, successful: 1, failed: 5, pended: 3, skipped: 6))
      expect(run.test_output.stdout).to include("Randomized with seed 35888")
      expect(formatted_test_result_output(run.results)).to match_snapshot(snapshot_name(example, "test-results"))
    end

    it "quits early if configured with fail-fast" do
      run = abq_test("bundle exec rspec --pattern 'spec/fixture_specs/*_specs.rb' --fail-fast", queue_address: AbqQueue.address, run_id: run_id)

      expect(run.test_output.exit_status).to eq(1)
      expect(run.test_output.stderr).to include("rspec-abq doesn't presently support running with fail-fast enabled")
    end

    context "with headless chrome" do
      it "has consistent output with capybara" do |example|
        EnvHelper.with_env("USE_SELENIUM" => "true") do
          run = abq_test("bundle exec rspec spec/fixture_specs/spec_with_capybara.rb", queue_address: AbqQueue.address, run_id: run_id)

          summary = run.results.fetch("summary")
          expect(summary.fetch("status")["kind"]).to eq("failed")
          expect(summary).to include(summary_counts(tests: 2, successful: 1, failed: 1))
          expect(run.results["tests"].count).to eq(2)
          expect(sorted_dots(run.test_output.stdout)).to match(/^\.F$/)
          expect(formatted_test_result_output(run.results)).to match_snapshot(snapshot_name(example, "test-results"))
        end
      end

      # TODO: If we detect these screenshots, perhaps we should forward them to the test runner.
      it "has consistent output with capybara & capybara-inline-screenshot" do |example| # rubocop:disable RSpec/ExampleLength
        EnvHelper.with_env(
          "SAVE_SCREENSHOT" => "true", # enables capybara-inline-screenshot in `spec_with_capybara`
          "CAPYBARA_INLINE_SCREENSHOT" => "artifact", # tells capybara-inline-screenshot to not base-64 encode the screenshot directly to STDOUT.
          "SAVE_SCREENSHOT_ARTIFACT_DIR" => AbqQueue.output_directory
        ) do
          run = abq_test("bundle exec rspec spec/fixture_specs/spec_with_capybara.rb", queue_address: AbqQueue.address, run_id: run_id)

          summary = run.results.fetch("summary")
          expect(summary.fetch("status")["kind"]).to eq("failed")
          expect(summary).to include(summary_counts(tests: 2, successful: 1, failed: 1))
          expect(run.results["tests"].count).to eq(2)
          expect(sorted_dots(run.test_output.stdout)).to match(/^\.F$/)
          expect(run.test_output.stdout).to match(%r{HTML screenshot: file://tmp/test-results-\d+/screenshot_.*\.html})
          expect(run.test_output.stdout).to match(%r{Image screenshot: file://tmp/test-results-\d+/screenshot_.*\.png})
          expect(formatted_test_result_output(run.results)).to match_snapshot(snapshot_name(example, "test-results"))
        end
      end
    end

    context "with random ordering", :aggregate_failures do
      # this one _does_ test rspec-abq's handling of random ordering
      it "has consistent output for random ordering passed as CLI argument" do |example|
        run = abq_test("bundle exec rspec spec/fixture_specs/successful_specs.rb spec/fixture_specs/pending_specs.rb --order rand", queue_address: AbqQueue.address, run_id: run_id)

        summary = run.results.fetch("summary")
        expect(summary.fetch("status")["kind"]).to eq("successful")
        expect(summary).to include(summary_counts(tests: 4, successful: 1, pended: 3, skipped: 0))
        expect(sorted_dots(run.test_output.stdout)).to match(/^\.PPP$/)
        expect(run.test_output.stdout).to include("Randomized with seed")
        expect(formatted_test_result_output(run.results)).to match_snapshot(snapshot_name(example, "test-results"))
      end

      it "has consistent output for random ordering set in rspec config" do |example|
        run = abq_test("bundle exec rspec spec/fixture_specs/spec_that_sets_up_random_ordering.rb", queue_address: AbqQueue.address, run_id: run_id)

        summary = run.results.fetch("summary")
        expect(summary.fetch("status")["kind"]).to eq("successful")
        expect(summary).to include(summary_counts(tests: 2, successful: 1, pended: 1))
        expect(sorted_dots(run.test_output.stdout)).to match(/^\.P$/)
        expect(run.test_output.stdout).to include("Randomized with seed")
        expect(formatted_test_result_output(run.results)).to match_snapshot(snapshot_name(example, "test-results"))
      end

      it "has consistent output for random seed set in rspec config" do |example|
        run = abq_test("bundle exec rspec spec/fixture_specs/spec_that_sets_up_random_seed.rb", queue_address: AbqQueue.address, run_id: run_id)

        summary = run.results.fetch("summary")
        expect(summary.fetch("status")["kind"]).to eq("successful")
        expect(summary).to include(summary_counts(tests: 2, successful: 1, pended: 1))
        expect(sorted_dots(run.test_output.stdout)).to match(/^\.P$/)
        expect(run.test_output.stdout).to include("Randomized with seed")
        expect(formatted_test_result_output(run.results)).to match_snapshot(snapshot_name(example, "test-results"))
      end
    end

    context "with syntax errors" do
      version = Gem::Version.new(RSpec::Core::Version::STRING)
      # we don't properly fail on syntax errors for versions 3.6, 3.7, and 3.8
      pending_test = version >= Gem::Version.new("3.6.0") && version < Gem::Version.new("3.9.0")

      it "has consistent output with syntax errors" do
        pending("incompatible with rspec 3.6-3.8") if pending_test

        run = abq_test("bundle exec rspec 'spec/fixture_specs/specs_with_syntax_errors.rb'", queue_address: AbqQueue.address, run_id: run_id)

        expect(run.test_output.exit_status).to eq(1)
        expect(run.test_output.stdout).to include("SyntaxError")
      end

      # this one doesn't even pass if pending for 3.6-3.8 so we skip it with metadata
      it "has consistent output with all specs including a syntax error", *[(:skip if pending_test)].compact do
        run = abq_test("bundle exec rspec --pattern 'spec/fixture_specs/**/*.rb'", queue_address: AbqQueue.address, run_id: run_id)

        expect(run.test_output.exit_status).to eq(1)
        expect(run.test_output.stdout).to include("SyntaxError")
      end
    end
  end
end
