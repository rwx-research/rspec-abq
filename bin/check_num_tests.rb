#!/usr/bin/env ruby

# rspec-abq calls exit(0). Loading the code path that calls exit(0) returns from rspec immediately with a exit status of 0
# which shows as "passing" in CI even if tests failed.
#
# Here, we compare the number of tests run to the expected number.

EXPECTED_TEST_NUMBER_SNAPSHOT_PATH = 'spec/NUM_TESTS'

json_path = ARGV[0]
unless File.exist?(json_path)
  warn "no test file found at #{json_path}"
  warn "usage: bin/check_num_tests.rb ./path-to-json-file"
  exit 1
end

require 'json'

expected_num_tests = File.read(EXPECTED_TEST_NUMBER_SNAPSHOT_PATH).strip.to_i

parsed = JSON.parse(File.read(json_path))
actual_num_tests =
  if parsed.key?("examples")
    parsed["examples"].length
  elsif parsed.key?("summary")
    parsed["summary"]["tests"]
  else
    warn "could not find examples or summary.test_count in #{json_path}"
    exit 1
  end

if actual_num_tests != expected_num_tests
  warn "We ran #{actual_num_tests} tests, but expected to run #{expected_num_tests}."
  exit 1
end

puts "We ran #{actual_num_tests} tests, as expected."
