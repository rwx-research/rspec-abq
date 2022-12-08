#!/usr/bin/env ruby

require 'fileutils'

Dir['spec/**/__snapshots__/*'].each do |file|
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

Dir['spec/**/*-rspec-3.12.gemfile.snap'].each do |path|
  Dir.chdir(File.dirname(path)) do
    source = File.basename(path)
    target = source.sub('rspec-3.12.gemfile', 'Gemfile')
    FileUtils.rm(target) if File.exist? target
    FileUtils.ln_s(source, target)
  end
end
