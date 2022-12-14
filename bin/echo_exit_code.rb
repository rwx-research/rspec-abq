#!/usr/bin/env ruby

# abq uses test results to determine whether to exit with 0 or 1.
# this echos the exit code for comparing with in tests

system(*ARGV)

puts "exit code: #{$?.exitstatus}"
