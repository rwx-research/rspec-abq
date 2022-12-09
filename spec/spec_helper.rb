require "bundler/setup"
require "rspec/abq"
require "rspec/snapshot"

require_relative "support/env_helper"
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
