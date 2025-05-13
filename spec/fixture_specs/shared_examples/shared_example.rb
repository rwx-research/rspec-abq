require 'spec_helper'

RSpec.shared_examples_for 'a shared example' do
  it 'has a shared test' do
    expect(true).to eq(true)
  end
end
