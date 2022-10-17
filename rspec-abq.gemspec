
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rspec/abq/version"

Gem::Specification.new do |spec|
  spec.name          = "rspec-abq"
  spec.version       = Rspec::Abq::VERSION
  spec.authors       = ["Michael Glass"]
  spec.email         = ["me@mike.is"]

  spec.summary       = %q{RSpec::Abq allows for parallel rspec runs using abq}
  spec.description   = %q{RSpec::Abq is an rspec plugin that replaces its ordering with one that is controlled by abq. It allows for parallelization of rspec on a single machine or across multiple workers.}
  spec.homepage      = "http://www.rwx.com"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "rspec-core", "~> 3.0"
  spec.add_development_dependency "bundler", "~> 1.17"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
