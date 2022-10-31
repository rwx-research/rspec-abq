#!/usr/bin/env ruby

GEMFILES = Dir['gemfiles/*.gemfile'] + ["Gemfile"]

GEMFILES.each do |gemfile|
  ENV['BUNDLE_GEMFILE'] = gemfile
  puts gemfile
  puts `bundle update`
end
