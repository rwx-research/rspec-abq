# called `_specs.rb` to avoid it being called automatically
# used by feature specs
RSpec.describe 'group 2' do
  it 'filtered out example 1', :if => false do end
  it 'filtered in example 2', :if => true do end
  xdescribe 'pending group 2-1' do
    it 'group 2-1 example 1' do end
    it 'group 2-1 example 2' do end
  end
end
