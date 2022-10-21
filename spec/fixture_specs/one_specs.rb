require 'spec_helper'
# called `_specs.rb` to avoid it being called automatically
# used by integration/abq_spec.rb
RSpec.describe 'group 1' do
  it 'example 1 with tags', :foo, :bar do end
  it 'example 2 with tag and value', :foo, bar: 5 do end
  describe 'group 1-1 with tags', :foo  do
    xit 'pending group 1-1 example 1' do end
    it 'group 1-1 example 2' do end
  end
  describe 'filtered out empty group' do
    describe 'filtered out nested empty group' do end
  end
end