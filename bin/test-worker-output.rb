#!/usr/bin/env ruby

unless $stdin.stat.pipe?
  warn 'Must be called via a pipe'
  exit 1
end

output = $stdin.read
output.each_line do |line|
  next if line.start_with?("Worker started with id ") || line.include?(" warning: ")
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
