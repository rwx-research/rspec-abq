#!/usr/bin/env ruby

require_relative "../lib/rspec/abq/version"
require "tempfile"
require "yaml"

def run_and_print(cmd)
  puts "$ #{cmd}"
  puts `#{cmd}`
end

GEM_NAME = "rspec-abq"

gh_auth_path = "#{ENV["HOME"]}/.config/gh/hosts.yml"

github_token = File.exist?(gh_auth_path) && YAML.load_file(gh_auth_path).dig("github.com", "oauth_token")

unless github_token
  if `which gh`.empty?
    puts "this script requires github cli to function. Installing...\n"
    run_and_print("brew install gh")
  end

  unless system("gh auth status")
    puts "you need to auth with the github before running this script...\n"
    # exec yields the ruby process so that `gh auth login` is automatic
    exec("gh auth login")
  end
end

unless system("gem signin --silent")
  puts "you aren't signed into rubygems. Please sign in ..."
  exec("gem signin")
end

unless `git status --porcelain`.empty?
  puts "Uncommitted changes found. Please commit or stash. Aborting."
  exit(1)
end

puts "💎releasing a new version of version of #{GEM_NAME}!💎"

latest_released_version = `gem info -r #{GEM_NAME}`.match(/\((\d+[^)]+)\)/)&.[](1)
if latest_released_version
  puts "latest released version is #{latest_released_version}"
  run_and_print "gem owner #{GEM_NAME}"
  puts "are you one of the owners? (y/n): "
  if gets.chomp.downcase != "y"
    puts "please ask one of the owners for access
    they can add you with `gem owner rspec-abq --add an@email.com`
    "
    exit(1)
  end
else
  puts "no released version yet! Welcome to the illustrious world of gem publishing"
end

current_branch = `git branch --show-current`.chomp

VERSION_PROMPT = <<~VERSION_PROMPT
  🔢version in `RSpec::Abq::VERSION is the same as the latest version.
  do you want to ...
  1: bump the PATCH version %{major}.%{minor}.%{bumped_patch}
  2: bump the MINOR version %{major}.%{bumped_minor}.0
  3: bump the MAJOR version %{bumped_major}.0.0
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
    ["minor", [major, minor + 1, 0].join(".")]
  when "3"
    ["major", [major + 1, 0, 0].join(".")]
  end

  if current_branch == "main"
    puts "Can't commit directly to main, opening a new branch"
    run_and_print("git checkout -b prep-for-#{version_to_release}")
  end

  run_and_print("gem bump --version #{what_to_bump}")
  run_and_print("bin/update_gemfiles.rb") # update gemfile.lock
  run_and_print("git add Gemfile.lock gemfiles")
  run_and_print("git commit --amend --no-edit")
  run_and_print("git push origin HEAD")
  run_and_print(%(gh pr create --title "prepare release v#{version_to_release}" --fill))
  puts "Now: merge a PR with this version and then continue releasing the gem from the main branch."
  exit(0)
end

unless current_branch == "main"
  puts "Can only release the gem from the main branch"
  exit(1)
end

run_and_print("gem tag --sign --push")

RELEASE_TEMPLATE = <<~RELEASE_TEMPLATE
  # 🙈 #{version_to_release} Title of Github Release Prefixed By Version and Fun Emoji!


  PLEASE REPLACE THIS RELEASE TEMPLATE. IT WILL POPULATE THE GITHUB RELEASE !

  In This Release, we did some excellent things.

  # 🪙 Changelog 🪵
  ## Bugs
  - fixed a cool bug [#000]
  ## Enhancements
  - now we can do spacetravel[#000]
RELEASE_TEMPLATE

Tempfile.create do |f|
  f.write(RELEASE_TEMPLATE)
  f.rewind

  `#{ENV["VISUAL"] || ENV["EDITOR"] || "nano"} #{f.path}`
  f.rewind

  puts "please enter your rubygems OTP"
  otp = gets.chomp
  until otp =~ /^\d{6}$/
    puts "otp is the wrong format"
    otp = gets.chomp
  end

  ENV["GEM_HOST_OTP_CODE"] = otp

  run_and_print(%{gem release --token #{github_token} --github --description "$(<#{f.path})"})
end

if $?.success?
  puts "🎉 released! 🎉"
else
  puts "💣 something might have gone wrong ... 🧨"
end
