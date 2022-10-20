# this is not a real test, but a fixture used by CI and by manifest_spec.rb
RSpec.describe 'group 2' do
  it 'filtered out example 1', :if => false do end
  it 'filtered in example 2', :if => true do end
  xdescribe 'pending group 2-1' do
    it 'group 2-1 example 1' do end
    it 'group 2-1 example 2' do end
  end
end
