require_relative "../spec_helper"
# called `_specs.rb` to avoid it being called automatically
# used by feature specs
RSpec.describe 'a successful group' do
  it 'has a successful test' do
    expect(true).to eq(true)
  end
end
