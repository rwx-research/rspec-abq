#!/usr/bin/env ruby

# rspec-abq calls exit(0). Loading the code path that calls exit(0) returns from rspec immediately with a exit status of 0
# which shows as "passing" in CI even if tests failed.
#
# Here, we compare the number of tests run to the expected number.

DEFAULT_TEST_JSON_PATH = 'tmp/rspec.json'
EXPECTED_TEST_NUMBER_SNAPSHOT_PATH = 'spec/NUM_TESTS'

json_path = ARGV[0] || DEFAULT_TEST_JSON_PATH
unless File.exist?(json_path)
  warn "no test file found at #{json_path}"
  warn "usage: bin/snapshot_num_tests.rb (path to json file) (default: #{DEFAULT_TEST_JSON_PATH}"
  exit 1
end

require 'json'

actual_num_tests = JSON.parse(File.read(json_path))['examples'].length
expected_num_tests = File.read(EXPECTED_TEST_NUMBER_SNAPSHOT_PATH).strip.to_i

if actual_num_tests != expected_num_tests
  warn "We ran #{actual_num_tests} tests, but expected to run #{expected_num_tests}."
  exit 1
end

puts "We ran #{actual_num_tests} tests, as expected."
