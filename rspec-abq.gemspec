# frozen_string_literal: true

require_relative "lib/rspec/abq/version"

Gem::Specification.new do |spec|
  spec.name = "rspec-abq"
  spec.version = RSpec::Abq::VERSION
  spec.authors = ["Ayaz Hafiz", "Michael Glass"]
  spec.email = ["ayaz@rwx.com", "me@rwx.com"]

  spec.summary = "RSpec::Abq allows for parallel rspec runs using abq"
  spec.description = "RSpec::Abq is an rspec plugin that replaces its ordering with one that is controlled by abq. It allows for parallelization of rspec on a single machine or across multiple workers."
  spec.homepage = "http://www.rwx.com"
  spec.license = "MIT"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rwx-research/rspec-abq"
  spec.metadata["changelog_uri"] = "https://github.com/rwx-research/rspec-abq/releases"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path("..", __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rspec-core", "~> 3.0"
end
