# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "kitchen/verifier/pester_version"

Gem::Specification.new do |spec|
  spec.name = "kitchen-pester"
  spec.required_ruby_version = ">= 3.1"
  spec.version       = Kitchen::Verifier::PESTER_VERSION
  spec.authors       = ["Steven Murawski"]
  spec.email         = ["steven.murawski@gmail.com"]
  spec.summary       = "Test-Kitchen verifier for Pester."
  spec.description   = "Skip all that Busser stuff and jump right into Pester."
  spec.homepage      = "https://github.com/test-kitchen/kitchen-pester"
  spec.license       = "MIT"

  spec.files         = %w{LICENSE kitchen-pester.gemspec} + Dir.glob("lib/**/*")
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest",  ">= 5.25", "< 7"
  spec.add_development_dependency "mocha",     ">= 2.0", "< 4"
  spec.add_development_dependency "yard",      "~> 0.9"
  # 3.6.0 is the first release to require Ruby >= 3.1, which this gem also
  # requires, so anything older cannot be installed alongside it in practice.
  spec.add_dependency "test-kitchen", ">= 3.6", "< 5"
end
