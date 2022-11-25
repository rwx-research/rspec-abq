require "open3"
require "spec_helper"

RSpec.describe "abq test" do # rubocop:disable RSpec/DescribeClass
  def abq_with(rspec_command, identifier)
    run_id = ENV["RUN_ID"] && "--run-id #{ENV["RUN_ID"]}-#{identifier} "
    command = "abq test --reporter dot #{run_id}-- #{rspec_command}"
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

  def stderr_matcher(stderr)
    expect(stderr.lines).to all(match(/warning: |(?:^Worker started)/))
  end

  it "has consistent output for success" do
    stdout, stderr, status = abq_with("bundle exec rspec --out /dev/null 'spec/fixture_specs/two_specs.rb'", "success")
    write_or_match("success", sanitize_output(stdout))
    stderr_matcher(stderr)
    expect(status.exitstatus).to eq(0)
  end

  it "has consistent output for failure" do
    stdout, stderr, status = abq_with("bundle exec rspec --out /dev/null --pattern 'spec/fixture_specs/*_specs.rb'", "failure")
    write_or_match("failure", sanitize_output(stdout))
    stderr_matcher(stderr)
    expect(status.exitstatus).to eq(1)
  end
end
