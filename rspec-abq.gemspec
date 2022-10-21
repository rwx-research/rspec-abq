# frozen_string_literal: true

require_relative "lib/rspec/abq/version"

Gem::Specification.new do |spec|
  spec.name = "rspec-abq"
  spec.version = RSpec::Abq::VERSION
  spec.authors = ["Ayaz Hafiz", "Michael Glass"]
  spec.email = ["ayaz@rwx.com", "me@rwx.com"]

  spec.summary = "RSpec::Abq allows for parallel rspec runs using abq"
  spec.description = "RSpec::Abq is an rspec plugin that replaces its ordering with one that is controlled by abq. It allows for parallelization of rspec on a single machine or across multiple workers."
  spec.homepage = "https://github.com/rwx-research/rspec-abq"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "bug_tracker_uri" => "https://github.com/rwx-research/rspec-abq/issues",
    "changelog_uri" => "https://github.com/rwx-research/rspec-abq/releases",
    "documentation_uri" => "https://rwx-research.github.io/rspec-abq/",
    "source_code_uri" => "https://github.com/rwx-research/rspec-abq"
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files` loads the files in the RubyGem that have been added into git.
  spec.files = `git ls-files -- lib/*`.split("\n") + %w[README.md]
  spec.require_paths = ["lib"]

  spec.add_dependency "rspec-core", "~> 3.11.0"
end
