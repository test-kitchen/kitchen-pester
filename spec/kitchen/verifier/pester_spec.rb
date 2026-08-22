# frozen_string_literal: true

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

require_relative "../../spec_helper"

# Covers the verifier's public surface: the config contract, construction, the
# four command hooks Test Kitchen calls, and the download-on-failure behaviour
# that wraps them.
describe Kitchen::Verifier::Pester do
  describe "plugin metadata" do
    it "declares verifier API version 1" do
      _(build_verifier.diagnose_plugin[:api_version]).must_equal 1
    end

    it "reports the gem version as its plugin version" do
      _(build_verifier.diagnose_plugin[:version]).must_equal Kitchen::Verifier::PESTER_VERSION
    end

    it "exposes a SemVer-shaped version string" do
      _(Kitchen::Verifier::PESTER_VERSION).must_match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe "#initialize" do
    it "accepts a hash of environment variables" do
      verifier = build_verifier({ environment: { "FOO" => "bar" } })

      _(verifier.send(:config)[:environment]).must_equal({ "FOO" => "bar" })
    end

    it "defaults the environment to an empty hash" do
      _(build_verifier.send(:config)[:environment]).must_equal({})
    end

    it "rejects an environment that is not a hash" do
      error = _ { Kitchen::Verifier::Pester.new({ environment: %w{FOO=bar} }) }
        .must_raise Kitchen::ClientError

      _(error.message).must_include "Environment Variables must be specified as a hash"
    end

    it "names the offending type in the error" do
      error = _ { Kitchen::Verifier::Pester.new({ environment: "FOO=bar" }) }
        .must_raise Kitchen::ClientError

      _(error.message).must_include "not a String"
    end
  end

  describe "default config" do
    let(:config) { build_verifier.send(:config) }

    it "looks for tests under ./tests" do
      _(config[:test_folder]).must_equal "tests"
    end

    it "removes the in-box PowerShellGet and Pester" do
      _(config[:remove_builtin_powershellget]).must_equal true
      _(config[:remove_builtin_pester]).must_equal true
    end

    it "installs Pester unless told otherwise" do
      _(config[:skip_pester_install]).must_equal false
    end

    it "does not restart WinRM unless asked" do
      _(config[:restart_winrm]).must_equal false
    end

    it "bootstraps from the public gallery with no extra modules" do
      _(config[:bootstrap]).must_equal({
        repository_url: "https://www.powershellgallery.com/api/v2",
        modules: [],
      })
    end

    it "downloads the NUnit results into ./testresults/" do
      _(config[:downloads]).must_equal({ "./PesterTestResults.xml" => "./testresults/" })
    end

    it "asks Pester for detailed output and a PassThru result object" do
      _(config[:pester_configuration][:Output][:Verbosity]).must_equal "Detailed"
      _(config[:pester_configuration][:run][:PassThru]).must_equal true
    end

    it "starts with no repositories, modules or copied folders" do
      _(config[:register_repository]).must_equal []
      _(config[:install_modules]).must_equal []
      _(config[:copy_folders]).must_equal []
    end
  end

  describe "#init_command" do
    it "returns nil when restart_winrm is off" do
      _(build_verifier.init_command).must_be_nil
    end

    it "schedules a WinRM restart when asked on Windows" do
      # Regression: #restart_winrm_service called `verifier.windows_os?`, but
      # `verifier` is a method on Instance, not on the verifier itself, so
      # setting restart_winrm raised NameError instead of doing anything.
      command = build_verifier({ restart_winrm: true }).init_command

      _(command).must_include "schtasks /Create /TN restart_winrm"
      _(command).must_include "Restart-Service winrm"
      _(command).must_include "schtasks /RUN /TN restart_winrm"
    end

    it "does nothing on a non-Windows platform even when restart_winrm is on" do
      verifier = build_verifier({ restart_winrm: true }, platform: PesterSpec::Helpers::UNIX_PLATFORM)

      _(verifier.init_command).must_be_nil
    end
  end

  describe "#prepare_command" do
    it "resolves the download paths before the run" do
      in_tmpdir do |dir|
        verifier = build_verifier({ downloads: { "./PesterTestResults.xml" => "#{dir}/out/" } })

        verifier.prepare_command

        _, destination = verifier.send(:config)[:downloads].first
        _(destination).must_equal "#{dir}/out/PesterTestResults.xml"
      end
    end

    it "wraps the bootstrap script for the target shell" do
      in_tmpdir do |dir|
        command = build_verifier({ downloads: { "./r.xml" => "#{dir}/out/" } }).prepare_command

        _(command).must_include "Import-Module -ErrorAction Stop PesterUtil"
        _(command).must_include "Set-Content -Path kitchen_cmd.ps1"
      end
    end
  end

  describe "#run_command" do
    let(:command) { build_verifier.run_command }

    it "wraps the Pester invocation for the target shell" do
      _(command).must_include "Set-Content -Path kitchen_cmd.ps1"
      _(command).must_include "powershell ./kitchen_cmd.ps1"
    end

    it "imports Pester before using it" do
      _(command).must_include "Import-Module -Name Pester -Force -ErrorAction Stop -PassThru"
    end

    it "propagates the Pester failure count as the exit code" do
      _(command).must_include "$LASTEXITCODE = $result.FailedCount"
      _(command).must_include "exit $LASTEXITCODE"
    end
  end

  describe "#invoke_pester_scriptblock" do
    let(:script) { build_verifier({ root_path: "/tmp/verifier" }).invoke_pester_scriptblock }

    it "runs the suites staged in the sandbox" do
      _(script).must_include %{$TestPath = Join-Path "/tmp/verifier" -ChildPath "suites"}
    end

    it "writes results next to the root path" do
      _(script).must_include %{$OutputFilePath = Join-Path "/tmp/verifier" -ChildPath 'PesterTestResults.xml'}
    end

    it "branches on the installed Pester major version" do
      _(script).must_include "if ($PesterModule.Version.Major -le 4)"
    end

    it "builds v4 parameters by intersecting config with Invoke-Pester's parameters" do
      _(script).must_include "$pesterCmd = Get-Command -Name 'Invoke-Pester'"
      _(script).must_include "foreach ($paramName in $pesterCmd.Parameters.Keys)"
      _(script).must_include "$result = Invoke-Pester @invokePesterParams"
    end

    it "builds a PesterConfiguration object for v5 and later" do
      _(script).must_include "$PesterConfig = New-PesterConfiguration -Hashtable $pesterConfigHash"
      _(script).must_include "$result = Invoke-Pester -Configuration $PesterConfig"
    end

    it "names the test suite after the instance in both branches" do
      _(script).must_include %{New-PesterOption -TestSuiteName "Pester - <pester-windows-2022>"}
      _(script).must_include "'Pester - <pester-windows-2022>'"
    end

    it "fills in run.path and TestResult defaults only when the user has not" do
      _(script).must_include "if (-not $pesterConfigHash.run.path)"
      _(script).must_include "if (-not $pesterConfigHash.TestResult.OutputPath)"
      _(script).must_include "if (-not $pesterConfigHash.TestResult.TestSuiteName)"
    end

    it "passes the configured environment variables through" do
      verifier = build_verifier({ environment: { "KITCHEN_SUITE" => "pester" } })

      _(verifier.invoke_pester_scriptblock).must_include "$env:KITCHEN_SUITE = 'pester'"
    end

    it "renders the pester_configuration hash as a PowerShell hashtable" do
      verifier = build_verifier({ pester_configuration: { Output: { Verbosity: "Diagnostic" } } })

      _(verifier.invoke_pester_scriptblock).must_include "'Verbosity' = 'Diagnostic'"
    end

    it "exports the result object to the path it just tested for" do
      # Regression: this was `Export-CliXml -Path` with no argument, which
      # fails parameter binding whenever result.xml happens to exist.
      _(script).must_include "$result | Export-CliXml -Path $resultXmlPath"
    end
  end

  describe "#call" do
    # Test Kitchen's base verifier downloads results in an ensure block only on
    # newer releases; on older ones Pester has to do it itself. Either way a
    # failing verify must still retrieve the results file.
    it "downloads the results when the run fails, then re-raises" do
      verifier = build_verifier
      verifier.stubs(:create_sandbox)
      verifier.stubs(:cleanup_sandbox)
      verifier.instance.transport.stubs(:connection).raises(Kitchen::ActionFailed, "boom")
      verifier.expects(:download_test_files).with({})

      _ { verifier.call({}) }.must_raise Kitchen::ActionFailed
    end

    it "skips the download when downloads are disabled" do
      verifier = build_verifier({ downloads: nil })
      verifier.stubs(:create_sandbox)
      verifier.stubs(:cleanup_sandbox)
      verifier.instance.transport.stubs(:connection).raises(Kitchen::ActionFailed, "boom")
      verifier.expects(:download_test_files).never

      _ { verifier.call({}) }.must_raise Kitchen::ActionFailed
    end
  end
end
