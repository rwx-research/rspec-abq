#!/usr/bin/env ruby

GEMFILES = Dir['gemfiles/*.gemfile'] + ["Gemfile"]

GEMFILES.map do |gemfile|
  Thread.new do
    ENV['BUNDLE_GEMFILE'] = gemfile
    puts `bundle lock --add-platform x86_64-linux`
  end
end.map(&:join)
