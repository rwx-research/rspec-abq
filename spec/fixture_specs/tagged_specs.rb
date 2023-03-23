require "spec_helper"
# called `_specs.rb` to avoid it being called automatically
# used by feature specs
RSpec.describe 'client-admin', client: :admin  do
  10.times do |i|
    it "admin test #{i}" do
      expect(true).to eq(true)
    end
  end
end

RSpec.describe 'client-portal', client: :portal do
  10.times do |i|
    it "portal test #{i}" do
      expect(true).to eq(true)
    end
  end
end
