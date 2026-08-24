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

  # README.md is what YARD picks up as the front page of the generated docs,
  # which is how rubydoc.info renders this gem.
  spec.files         = %w{LICENSE README.md kitchen-pester.gemspec} + Dir.glob("lib/**/*")
  spec.require_paths = ["lib"]

  # 3.6.0 is the first release to require Ruby >= 3.1, which this gem also
  # requires, so anything older cannot be installed alongside it in practice.
  spec.add_dependency "test-kitchen", ">= 3.6", "< 5"
end
