require "spec_helper"
# called `_specs.rb` to avoid it being called automatically
# used by feature specs
RSpec.describe 'skipped tests' do
  xit 'skipped test with xit' do
    expect(false).to eq(true)
  end

  it 'has a skipped test with skip' do
    skip
    expect(false).to eq(true)
  end

  it 'skipped test with tag', :skip do
    expect(false).to eq(true)
  end

  describe 'a skipped group via tag', :skip do
    it 'is skipped despite not being marked as skip' do
      expect(false).to eq(true)
    end
  end

  xdescribe 'skipped group with xdescribe' do
    it 'is skipped despite not being marked as skip' do
      expect(false).to eq(true)
    end
  end

  describe 'skipped in a before block' do
    before(:all) { skip('because') }

    it "is skipped despite not being marked as skip" do
      expect(false).to eq(true)
    end
  end
end
