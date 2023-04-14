# RSpec bindings for ABQ

:globe_with_meridians: [abq.build](https://abq.build) &ensp;
:bird: [@rwx_research](https://twitter.com/rwx_research) &ensp;
:speech_balloon: [discord](https://www.rwx.com/discord) &ensp;
:books: [documentation](https://www.rwx.com/docs/abq)

[ABQ](https://github.com/rwx-research/abq) is a universal test runner that runs test suites in parallel.
It’s the best tool for splitting test suites into parallel jobs locally or on CI.

The `rspec-abq` gem provides the RSpec bindings for ABQ.

To use ABQ, check out the documentation on [getting started](https://www.rwx.com/docs/abq/getting-started).

## Demo

Here's a demo of running an RSpec test suite, and then using `abq` to run it in parallel.
ABQ invokes any test command passed to it, so you can continue using your native test framework CLI with any arguments it supports.

![abq-demo.svg](abq-demo.svg)

## Installation

Include the `rspec-abq` gem in your `Gemfile`.
Commonly, it's added under a test group.

```ruby
group :test do
  gem "rspec-abq"
end
```

See [the docs](https://www.rwx.com/docs/abq/test-frameworks/rspec) for more notes on installation and compatibility with other RSpec libraries.

## Development

For working on `rspec-abq` itself, see [DEVELOPMENT.md](DEVELOPMENT.md)

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/rwx-research/rspec-abq>. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## Code of Conduct

Everyone interacting in the Rspec::Abq project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/rwx-research/rspec-abq/blob/master/CODE_OF_CONDUCT.md).
