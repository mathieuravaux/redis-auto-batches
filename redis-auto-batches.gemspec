# -*- encoding: utf-8 -*-
require File.expand_path('../lib/redis-auto-batches/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Mathieu Ravaux", "Sylvain Lemière", "Jeremy Van Der Wyngaert"]
  gem.email         = ["mathieu.ravaux@gmail.com"]
  gem.description   = %q{Automatically and painlessly batch your redis commands for performance}
  gem.summary       = %q{TODO: Write a gem summary}
  gem.homepage      = "http://github.com/mathieuravaux/redis-auto-batches"

  gem.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  gem.files         = `git ls-files`.split("\n")
  gem.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  gem.name          = "redis-auto-batches"
  gem.require_paths = ["lib"]
  gem.version       = Redis::Auto::Batches::VERSION

  gem.add_dependency("redis")
  
  gem.add_development_dependency("rake")
  gem.add_development_dependency("rspec")
end
