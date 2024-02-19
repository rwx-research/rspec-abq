# frozen_string_literal: true

require_relative "lib/rspec/abq/version"

Gem::Specification.new do |spec|
  spec.name = "rspec-abq"
  spec.version = RSpec::Abq::VERSION
  spec.authors = ["Ayaz Hafiz", "Michael Glass"]
  spec.email = ["ayaz@rwx.com", "me@rwx.com"]
  spec.license = "MIT"

  spec.summary = "RSpec::Abq allows for parallel rspec runs using abq"
  spec.description = "RSpec::Abq is an rspec plugin that replaces its ordering with one that is controlled by abq. It allows for parallelization of rspec on a single machine or across multiple workers."
  spec.homepage = "https://github.com/rwx-research/rspec-abq"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "bug_tracker_uri" => "https://github.com/rwx-research/rspec-abq/issues",
    "changelog_uri" => "https://github.com/rwx-research/rspec-abq/releases",
    "documentation_uri" => "https://rwx-research.github.io/rspec-abq/",
    "source_code_uri" => "https://github.com/rwx-research/rspec-abq",
    "rubygems_mfa_required" => "true"
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files` loads the files in the RubyGem that have been added into git.
  spec.files = `git ls-files -- lib/*`.split("\n") + %w[README.md LICENSE.md]
  spec.require_paths = ["lib"]

  spec.add_dependency "rspec-core", ">= 3.5.0", "< 3.13.0"
  spec.add_development_dependency "pry", "~> 0.14.1"
  spec.add_development_dependency "rspec-retry", "~> 0.6.2"
  spec.add_development_dependency "capybara", "~> 3.38.0"
  spec.add_development_dependency "selenium-webdriver", "~> 4.8.0"
  spec.add_development_dependency "nokogiri", "~> 1.14.2"
  spec.add_development_dependency "webdrivers", "~> 5.3"
  spec.add_development_dependency "rack", "~> 2.2.6.4"
  spec.add_development_dependency "puma", "~> 6.1.0"
  spec.add_development_dependency "capybara-inline-screenshot", "~> 2.2.1"
  spec.add_development_dependency "simplecov", "~> 0.22.0"
end
