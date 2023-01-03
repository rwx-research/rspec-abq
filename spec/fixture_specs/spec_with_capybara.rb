# note this file doesn't end with _specs.rb so it won't be run by default

require 'spec_helper'
require 'capybara/rspec'

class Application
  def self.call(env)
    status  = 200
    headers = { "Content-Type" => "text/html" }
    body    = ["A tiny website"]

    [status, headers, body]
  end
end

Capybara.app = Application

if ENV['USE_SELENIUM']
  require 'webdrivers/chromedriver'
  Capybara.default_driver = :selenium_chrome_headless
end

RSpec.describe 'a spec with capybara', type: :feature do
  it 'can succeed' do
    visit "/"
    expect(page).to have_content("A tiny website")
  end

  it 'can fail' do
    visit "/"
    expect(page).to have_content("A huge website")
  end
end
