# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in rspec-abq.gemspec
gemspec

# and the specific patch version of rspec
gem "rspec", "~> 3.13"

group :development do
  gem "rake", "~> 13.0"
  gem "ruby-lsp"
  gem "rubocop", require: false
  # and a bunch of rubocop plugins
  gem "rubocop-performance", require: false
  gem "rubocop-rake", require: false
  gem "rubocop-rspec", require: false
  gem "standard", ">=1.20.0", require: false # without this 1.20.0, sometimes standard.rb will revert to 0.0.36
  gem "yard", require: false
  gem "gem-release", require: false
  gem "rspec-snapshot", github: "rwx-research/rspec-snapshot"
end
