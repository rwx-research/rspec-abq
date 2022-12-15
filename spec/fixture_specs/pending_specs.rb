require "spec_helper"
# called `_specs.rb` to avoid it being called automatically
# used by feature specs
RSpec.describe 'a pending group' do
  xit 'has a pending test with xit' do
    expect(false).to eq(true)
  end

  it 'has a pending test with pending' do
    pending
    expect(false).to eq(true)
  end

  xdescribe 'has a pending group' do
    it 'is pending despite not being marked as pending' do
      expect(false).to eq(true)
    end
  end
end
