require 'spec_helper'
# called `_specs.rb` to avoid it being called automatically
# used by feature specs

require_relative './shared_examples/shared_example.rb'

RSpec.describe 'a shared group' do
  it_behaves_like 'a shared example'
end
