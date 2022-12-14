#!/usr/bin/env ruby

# abq uses test results to determine whether to exit with 0 or 1.
# abq (as far as I know?) ignores the native runner's exit status.
#
# this echos the native runner's exit status so we can assert against it in the tests.

system(*ARGV)

puts "exit status: #{$?.exitstatus}"
