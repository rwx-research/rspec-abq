#!/usr/bin/env ruby

# abq uses test results to determine whether to exit with 0 or 1.
# abq (as far as I know?) ignores the native runner's exit code.
#
# this echos the native runner's exit code to ensure it's what we want in the test code.

system(*ARGV)

puts "exit code: #{$?.exitstatus}"
