#!/usr/bin/env ruby

require 'open3'
success_or_failure = ARGV[0]

run_id = "#{ENV['RUN_ID']}-#{success_or_failure}}"

command = "abq work --run-id #{run_id} -n cpu-cores"
puts "Running: #{command}"
output, status = Open3.capture2(command)
output.each_line do |line|
  next if line.start_with?("Worker started with id ") || line.include?(" warning: ") || line.match?(/INFO\s*\033\[0m\s*abq_workers/)
  warn "=================="
  warn "unexpected output:"
  warn "=================="
  warn line
  warn "================="
  warn "complete output:"
  warn "================="
  warn output
  exit 1
end

puts output

should_succeed = success_or_failure  == "success"
exit 1 if should_succeed != status.success?
