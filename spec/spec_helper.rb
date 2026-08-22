# Copyright (c) 2015 Steven Murawski
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# Shared setup for the kitchen-pester unit specs.
#
# The verifier is, almost entirely, a PowerShell string builder: it turns
# kitchen.yml config into script text that a remote SUT executes. That makes it
# cheap to test for real -- no VM, no WinRM, no network. These helpers build a
# genuine Kitchen::Instance around the verifier so that `windows_os?`,
# `instance.to_str` and friends behave exactly as they do in production, rather
# than being papered over with a subclass or a stub.

require "minitest/autorun"
require "mocha/minitest"

require "stringio" unless defined?(StringIO)
require "tmpdir" unless defined?(Dir.mktmpdir)
require "fileutils" unless defined?(FileUtils)

require "kitchen"
require "kitchen/driver/dummy"
require "kitchen/provisioner/dummy"
require "kitchen/transport/dummy"

require_relative "../lib/kitchen/verifier/pester"

module PesterSpec
  # Builds finalized verifiers wired to a real Kitchen::Instance.
  module Helpers
    WINDOWS_PLATFORM = { os_type: "windows", shell_type: "powershell" }.freeze
    UNIX_PLATFORM    = { os_type: "unix",    shell_type: "bourne"     }.freeze

    # Builds a Pester verifier attached to a real instance.
    #
    # @param config [Hash] verifier config, as it would appear under
    #   `verifier:` in kitchen.yml
    # @param platform [Hash] os_type/shell_type for the instance's platform
    # @param platform_name [String] name used to build the instance name
    # @param suite_name [String] name of the suite under test
    # @return [Kitchen::Verifier::Pester] a finalized verifier
    def build_verifier(config = {}, platform: WINDOWS_PLATFORM, platform_name: "windows-2022", suite_name: "pester")
      verifier = Kitchen::Verifier::Pester.new(config)
      build_instance(verifier, platform: platform, platform_name: platform_name, suite_name: suite_name)
      verifier
    end

    # Wraps an already-constructed verifier in an instance. Split out from
    # #build_verifier so that specs covering #initialize can construct the
    # verifier themselves and still get a working instance afterwards.
    #
    # @return [Kitchen::Instance] the instance the verifier is bound to
    def build_instance(verifier, platform: WINDOWS_PLATFORM, platform_name: "windows-2022", suite_name: "pester")
      state_file = Kitchen::StateFile.new(Dir.pwd, "#{suite_name}-#{platform_name}")

      Kitchen::Instance.new(
        suite: Kitchen::Suite.new(name: suite_name),
        platform: Kitchen::Platform.new({ name: platform_name }.merge(platform)),
        driver: Kitchen::Driver::Dummy.new({}),
        provisioner: Kitchen::Provisioner::Dummy.new({}),
        transport: Kitchen::Transport::Dummy.new({}),
        verifier: verifier,
        lifecycle_hooks: Kitchen::LifecycleHooks.new({}, state_file),
        state_file: state_file,
        logger: spec_logger
      )
    end

    # A logger that swallows output so specs do not spray the reporter. The
    # verifier calls info/debug liberally, and Kitchen.logger would otherwise
    # write those to stdout.
    #
    # @return [Kitchen::Logger] a silent logger
    def spec_logger
      @spec_logger ||= Kitchen::Logger.new(stdout: StringIO.new, level: :fatal)
    end

    # Whether the PowerShell parser is available to syntax-check generated
    # scripts. Memoized because it shells out.
    #
    # @return [Boolean] true when pwsh is on PATH
    def self.pwsh?
      return @pwsh unless @pwsh.nil?

      @pwsh = system(
        "pwsh", "-NoProfile", "-Command", "exit 0",
        out: File::NULL, err: File::NULL
      ) || false
    end

    # Yields a scratch directory that is removed afterwards, so no spec writes
    # into the working tree.
    #
    # @yieldparam dir [String] path to the temporary directory
    def in_tmpdir
      dir = Dir.mktmpdir("kitchen-pester-spec-")
      yield dir
    ensure
      FileUtils.rmtree(dir) if dir && Dir.exist?(dir)
    end

    # Normalizes generated PowerShell for comparison. The verifier builds its
    # scripts out of nested heredocs, so indentation is an artifact of how the
    # Ruby source happens to be laid out rather than something worth asserting
    # on.
    #
    # @param script [String] generated PowerShell
    # @return [String] the script with leading/trailing whitespace stripped
    #   from every line and blank lines removed
    def squish(script)
      script.to_s.lines.map(&:strip).reject(&:empty?).join("\n")
    end
  end
end

module Minitest
  class Spec
    include PesterSpec::Helpers
  end
end
