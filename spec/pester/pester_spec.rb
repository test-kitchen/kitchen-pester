# gem "minitest"
# require "minitest/autorun"
# require "mocha/setup"

require_relative "../../lib/kitchen/verifier/pester"

# class MockPester < Kitchen::Verifier::Pester
#   def sandbox_path
#     "C:/users/jdoe/temp/kitchen-temp"
#   end

#   def suite_test_folder
#     "C:/lowercasedpath/pester/tests"
#   end
# end

# describe "when sandboxifying a path" do
#   let(:sandboxifiedPath) do
#     pester = MockPester.new
#     pester.sandboxify_path("C:/LOWERcasedpath/Pester/tests/test")
#   end

#   it "should ignore case" do
#     _(sandboxifiedPath).must_equal "C:/users/jdoe/temp/kitchen-temp/suites/test"
#   end
# end
