#!/usr/bin/env ruby

GEMFILES = Dir['gemfiles/*.gemfile'] + ["Gemfile"]

GEMFILES.map do |gemfile|
  Thread.new do
    system({"BUNDLE_GEMFILE" => gemfile}, "bundle update")
  end
end.map(&:join)
