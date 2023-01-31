unless ENV.key?("NO_COVERAGE")
  require "simplecov"
  if ENV.key?("ABQ_SOCKET")
    # for nested rspec processes
    SimpleCov.at_fork.call(Process.pid)
  end

  SimpleCov.start do
    add_filter "/spec/"
  end
end

require "bundler/setup"
require "rspec/abq"
require "rspec/snapshot"
require "pry"

require "support/env_helper"
RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around do |example|
    example.run
  rescue SystemExit => e
    fail "you ran a test that called exit(#{e.status})"
  end
end
