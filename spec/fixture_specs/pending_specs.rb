require "spec_helper"
# called `_specs.rb` to avoid it being called automatically
# used by feature specs
RSpec.describe 'pending tests' do
  it 'has a pending test with pending' do
    pending('because')
    expect(false).to eq(true)
  end

  it 'has a pending test with a tag', :pending do
    expect(false).to eq(true)
  end

  describe 'a pending group via a tag', :pending do
    it 'is pending despite not being marked as pending' do
      expect(false).to eq(true)
    end
  end
end
