# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cloudpad/version'

Gem::Specification.new do |spec|
  spec.name          = "cloudpad"
  spec.version       = Cloudpad::VERSION
  spec.authors       = ["Alan Graham"]
  spec.email         = ["alan@productlab.com"]
  spec.summary       = %q{A deployment library for docker on CoreOS}
  spec.description   = %q{A deployment library for docker on CoreOS}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_dependency "capistrano", "3.2.1"
  spec.add_dependency "colored"
  spec.add_dependency "faraday"
  spec.add_dependency "activesupport"
end
