#!/usr/bin/env ruby

Dir['gemfiles/*.gemfile'].map do |gemfile|
  Thread.new do
    puts gemfile
    puts `BUNDLE_GEMFILE=#{gemfile} bundle exec rspec abq_spec/abq_test_spec.rb`
  end
end.map(&:join)
