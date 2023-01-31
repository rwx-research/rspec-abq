#!/usr/bin/env ruby

require 'fileutils'

# we `git rm` (as opposed to just rm) so that case-only changes are picked up.
`git rm -r spec/**/__snapshots__`

ENV['UPDATE_SNAPSHOTS'] = 'true'
ENV['NO_COVERAGE'] = 'true'
threads = Dir['gemfiles/*.gemfile'].map do |gemfile|
  Thread.new do
    system({"BUNDLE_GEMFILE" => gemfile}, "bundle exec rspec spec/features/integration_spec.rb")
  end
end

threads << Thread.new do
  system("bundle exec rspec spec/features/manifest_spec.rb")
end

threads.concat(Dir['gemfiles/*.gemfile'].map do |gemfile|
  Thread.new do
    system({"BUNDLE_GEMFILE" => gemfile}, "bundle exec rspec spec/features/test_result_spec.rb")
  end
end)

threads.map(&:join)

# rspec-abq calls exit(0). Loading the code path that calls exit(0) returns from rspec immediately with a exit status of 0
# which shows as "passing" in CI even if tests failed.
#
# Here, we count the tests without running them and save them in spec/NUM_TESTS.
# In CI, we fail the build if the number of tests in the results JSON isn't equal to this number.
`bundle exec rspec --dry-run --format json | jq '.examples | length' > spec/NUM_TESTS`

# symlink the results for the latest gemfile to the results for the default gemfile
Dir['spec/**/*-rspec-3.12.gemfile.snap'].each do |path|
  Dir.chdir(File.dirname(path)) do
    source = File.basename(path)
    target = source.sub('rspec-3.12.gemfile', 'Gemfile')
    FileUtils.rm(target) if File.exist? target
    FileUtils.ln_s(source, target)
  end
end

`git add spec/**/__snapshots__`
