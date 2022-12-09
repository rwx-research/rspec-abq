# Rspec::Abq

This gem helps you use rspec with abq.

## Installation

Add this line to your application's Gemfile:

```ruby
group :test do
    gem 'rspec-core'
    ...
    gem 'rspec-abq'
end
```

And then execute:

```bash
bundle
```

## Usage

Use the included binary with abq:

```bash
abq test -- bundle exec rspec
```

If abq displays "Worker quit before sending protocol version", try adding this line to your application's `spec/spec_helper.rb`:

```ruby
require 'rspec/abq'
```

## Compatibility

This gem is actively tested against rubies 2.6-3.1 and rspecs 3.5-3.12

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

### Releasing the gem

use the release script, `./release_gem.rb`

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/rwx-research/rspec-abq>. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## Code of Conduct

Everyone interacting in the Rspec::Abq project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/rwx-research/rspec-abq/blob/master/CODE_OF_CONDUCT.md).
