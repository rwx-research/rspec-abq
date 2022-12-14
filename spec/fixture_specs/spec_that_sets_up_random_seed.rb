
require 'rspec/abq'

RSpec.configure do |config|
  config.order = :random
  config.seed = rand(0xFFFF) # I don't know why someone would do this but if they do, we have a race condition
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
