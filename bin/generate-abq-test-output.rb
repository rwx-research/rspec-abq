#!/usr/bin/env ruby

require 'fileutils'

Dir['spec/test-outputs/*'].each do |file|
  FileUtils.rm file
end
Dir['gemfiles/*.gemfile'].map do |gemfile|
  Thread.new do
    ENV['BUNDLE_GEMFILE'] = gemfile
    ENV['UPDATE_SNAPSHOTS'] = 'true'
    puts(gemfile + ":" + `bundle exec rspec spec/features/integration_spec.rb`)
  end
end.map(&:join)

# symlink the results for the latest gemfile to the results for the default gemfile

Dir.chdir('spec/test-outputs') do
  Dir['*-rspec-3.12.gemfile.txt'].each do |source|
    target = source.sub('rspec-3.12.gemfile', 'Gemfile')
    FileUtils.rm(target) if File.exist? target
    FileUtils.ln_s(source, target)
  end
end
