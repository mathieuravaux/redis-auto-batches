#!/usr/bin/env rake

require "bundler"
require "bundler/gem_tasks"
Bundler.setup

require "rake"

require "rspec"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new('spec') do |spec|
  spec.pattern = "spec/**/*_spec.rb"
end

task :default => :spec
