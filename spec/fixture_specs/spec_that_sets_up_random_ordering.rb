
require 'rspec/abq'

RSpec.configure do |config|
  config.order = :random
end

RSpec.describe "random ordering" do
  it 'passes' do
    expect(true).to eq(true)
  end

  it 'is pended' do
    pending
    expect(true).to eq(false)
  end
end
