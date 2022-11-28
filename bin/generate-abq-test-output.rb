#!/usr/bin/env ruby

require 'fileutils'

Dir['gemfiles/*.gemfile'].map do |gemfile|
  Thread.new do
    puts gemfile
    ENV['BUNDLE_GEMFILE'] = gemfile
    ENV['UPDATE_SNAPSHOTS'] = 'true'
    puts `bundle exec rspec abq_spec/abq_test_spec.rb`
  end
end.map(&:join)

# symlink the results for the latest gemfile to the results for the default gemfile

Dir.chdir('abq_spec/test-outputs') do
  Dir['*-rspec-3.12.gemfile.txt'].each do |source|
    target = source.sub('rspec-3.12.gemfile', 'Gemfile')
    File.rm(target) if File.exist? target
    FileUtils.ln_s(source, target)
  end
end
