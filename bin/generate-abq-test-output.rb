#!/usr/bin/env ruby

Dir['gemfiles/*.gemfile'].map do |gemfile|
  Thread.new do
    puts gemfile
    ENV['BUNDLE_GEMFILE'] = gemfile
    ENV['UPDATE_SNAPSHOTS'] = 'true'
    puts `bundle exec rspec abq_spec/abq_test_spec.rb`
  end
end.map(&:join)
