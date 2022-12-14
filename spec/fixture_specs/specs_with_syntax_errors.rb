require_relative "../spec_helper"
# this file is named differently than all the other fixture_specs.rb so it doesn't get globbed with them
# if it gets loaded, no specs run
# used by feature specs
RSpec.describe 'with syntax errors" do
  it is getting pretty wacky in here do
    expect(syntax).to eq(the best)
  end
end
