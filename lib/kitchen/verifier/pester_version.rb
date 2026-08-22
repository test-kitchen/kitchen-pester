# Test Kitchen's top-level namespace.
module Kitchen
  # Namespace for Test Kitchen verifier plugins.
  module Verifier
    # Version of the kitchen-pester gem.
    #
    # Kept in its own file so that the gemspec can read it without loading
    # test-kitchen, which is not yet available when the gemspec is evaluated.
    #
    # @return [String] the gem version
    PESTER_VERSION = "1.2.0".freeze
  end
end
