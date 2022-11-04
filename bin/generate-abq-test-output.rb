#!/usr/bin/env ruby

Dir['gemfiles/*.gemfile'].map do |gemfile|
  Thread.new do
    ENV['BUNDLE_GEMFILE'] = gemfile
    output = `abq test --reporter dot -- bin/rspec_without_output_for_abq.sh`
    puts "#{gemfile}\n#{output}"
    rspec_version = File.basename(gemfile).split(".gemfile").first
    without_last_line = output.lines[0...-1].join
    File.write("test-outputs/#{rspec_version}.txt", without_last_line)
  end
end.map(&:join)
