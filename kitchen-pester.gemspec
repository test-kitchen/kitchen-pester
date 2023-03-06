lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "kitchen/verifier/pester_version"

Gem::Specification.new do |spec|
  spec.name          = "kitchen-pester"
  spec.version       = Kitchen::Verifier::PESTER_VERSION
  spec.authors       = ["Steven Murawski"]
  spec.email         = ["steven.murawski@gmail.com"]
  spec.summary       = "Test-Kitchen verifier for Pester."
  spec.description   = "Skip all that Busser stuff and jump right into Pester."
  spec.homepage      = "https://github.com/test-kitchen/kitchen-pester"
  spec.license       = "Apache-2.0"

  spec.files         = %w{LICENSE kitchen-pester.gemspec Gemfile Rakefile} + Dir.glob("lib/**/*")
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest",  "~> 5.3", "< 5.19"
  spec.add_development_dependency "mocha",     "~> 1.1"

  spec.add_dependency "test-kitchen", ">= 1.10", "< 4"
end
