require "open3"
# require "pry"
require "spec_helper"

RSpec.describe "abq test" do
  it "has consistent output for success"

  it "has consistent output for failure" do
    stdout, stderr, status = Open3.capture3("abq test --reporter dot -- bundle exec rspec --out /dev/null --pattern 'spec/fixture_specs/*_specs.rb'")
    gemfile_location = ENV["BUNDLE_GEMFILE"]
    test_identifier = "failure"
    file_path = "abq_spec/test-outputs/#{test_identifier}-#{File.basename(gemfile_location)}.txt"
    matchable_output = stdout.lines[0...-1].join # drop last line because it has timing information
    if File.exist?(file_path)
      expect(matchable_output).to eq(File.read(file_path))
    else
      File.write(file_path, matchable_output)
    end
  end
end
