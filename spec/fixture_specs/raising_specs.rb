require "spec_helper"
# called `_specs.rb` to avoid it being called automatically
# used by feature specs
RSpec.describe 'a raising group' do
  it 'has a raising test' do
    raise 'the roof'
  end

  context "it can handle an exception in a before all hook" do
    before(:all) do
      raise "raising from before(:all)"
    end

    it "should fail" do
      # should fail without running because of the exception in the before(:all)
      exit 9999
    end

    it "should also fail" do
      # should fail without running because of the exception in the before(:all)
      exit 9999
    end
  end
end
