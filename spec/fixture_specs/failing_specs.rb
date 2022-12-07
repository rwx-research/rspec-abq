require 'spec_helper'
# called `_specs.rb` to avoid it being called automatically
# used by feature specs
RSpec.describe 'a failing group' do
  it 'has a failing test' do
    expect(false).to eq(true)
  end
end
