require "spec_helper"
# called `_specs.rb` to avoid it being called automatically
# used by feature specs
RSpec.describe 'a raising group' do
  it 'has a raising test' do
    raise 'the roof'
  end
end
