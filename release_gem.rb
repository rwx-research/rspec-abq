#!/usr/bin/env ruby

require_relative "lib/rspec/abq/version"
require "tempfile"
require "yaml"

gh_auth_path = "#{ENV["HOME"]}/.config/gh/hosts.yml"

github_token = File.exist?(gh_auth_path) && YAML.load_file(gh_auth_path).dig("github.com", "oauth_token")

unless github_token
  if `which gh`.empty?
    puts "this script requires github cli to function. Installing...\n"
    `brew install gh`
  end

  unless system("gh auth status")
    puts "you need to auth with the github before running this script...\n"
    exec("gh auth login")
  end
end

unless `git status --porcelain`.empty?
  puts "Uncommitted changes found. Please commit or stash. Aborting."
  exit(1)
end

GEM_NAME = "rspec-abq"
puts "💎releasing a new version of version of #{GEM_NAME}!💎"

latest_released_version = `gem info -r #{GEM_NAME}`.match(/\((\d+[^)]+)\)/) & [1]
if latest_released_version
  puts "latest released version is #{latest_released_version}"
else
  puts "no released version yet! Welcome to the illustrious world of gem publishing"
end

def run_and_print(cmd)
  puts "$ #{cmd}"
  puts `#{cmd}`
end

VERSION_PROMPT = <<~VERSION_PROMPT
  🔢version in `RSpec::Abq::VERSION is the same as the latest version.
  do you want to ...
  1: bump the PATCH version %{major}.%{minor}.%{bumped_patch}
  2: bump the MINOR version %{major}.%{bumped_minor}.%{patch}
  3: bump the MAJOR version %{bumped_major}.%{minor}.%{patch}
  (1/2/3):
VERSION_PROMPT

version_to_release = RSpec::Abq::VERSION
if version_to_release == latest_released_version
  major, minor, patch = RSpec::Abq::VERSION.split(".").map(&:to_i)
  what_to_bump_num = nil
  loop do
    print(VERSION_PROMPT % {major: major, minor: minor, patch: patch, bumped_major: major + 1, bumped_minor: minor + 1, bumped_patch: patch + 1})
    what_to_bump_num = gets.chomp
    break if what_to_bump_num[/^[1,23]$/]
  end

  what_to_bump, version_to_release = case what_to_bump_num
  when "1"
    ["patch", [major, minor, patch + 1].join(".")]
  when "2"
    ["minor", [major, minor + 1, patch].join(".")]
  when "3"
    ["major", [major + 1, minor, patch + 1].join(".")]
  end
  run_and_print("gem bump --version #{what_to_bump}")
end

run_and_print("gem tag --push")

RELEASE_TEMPLATE = <<~RELEASE_TEMPLATE
  # 🙈 #{version_to_release} Title of Github Release Prefixed By Version and Fun Emoji!


  PLEASE REPLACE THIS RELEASE TEMPLATE. IT WILL POPULATE THE GITHUB RELEASE !

  In This Release, we did some excellent things.

  # 🪙 Changelog 🪵
  ## Bugs
  - fixed a cool bug [#123] (thanks @Janice !)
  ## Enhancements
  - now we can do spacetravel[#1337] (cheers to @Bobak ! )
RELEASE_TEMPLATE

Tempfile.create do |f|
  f.write(RELEASE_TEMPLATE)
  f.rewind

  `#{ENV["VISUAL"] || ENV["EDITOR"] || "nano"} #{f.path}`
  f.rewind

  run_and_print("gem release --token #{github_token} --github --description '$(<#{f.path})'")
end

puts "🎉 released! 🎉"
