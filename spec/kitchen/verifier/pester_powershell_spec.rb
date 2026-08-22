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

# Covers the primitives that turn Ruby values into PowerShell source. Everything
# else in the verifier is built on top of these, so a regression here silently
# corrupts every generated script.
describe Kitchen::Verifier::Pester do
  describe "#ps_hash" do
    let(:verifier) { build_verifier }

    it "renders true as a PowerShell boolean literal" do
      _(verifier.send(:ps_hash, true)).must_equal "$true"
    end

    it "renders false as a PowerShell boolean literal" do
      _(verifier.send(:ps_hash, false)).must_equal "$false"
    end

    it "single-quotes strings" do
      _(verifier.send(:ps_hash, "Stop")).must_equal "'Stop'"
    end

    it "coerces non-string scalars to quoted strings so PowerShell can re-infer the type" do
      _(verifier.send(:ps_hash, 5)).must_equal "'5'"
      _(verifier.send(:ps_hash, :Detailed)).must_equal "'Detailed'"
      _(verifier.send(:ps_hash, nil)).must_equal "''"
    end

    it "renders a hash as a PowerShell hashtable" do
      _(squish(verifier.send(:ps_hash, { Name: "Pester", Force: true })))
        .must_equal "@{\n'Name' = 'Pester'\n'Force' = $true\n}"
    end

    it "renders an array as a PowerShell array" do
      _(squish(verifier.send(:ps_hash, %w{one two}))).must_equal "@(\n'one','two'\n)"
    end

    it "recurses into nested hashes" do
      rendered = squish(verifier.send(:ps_hash, { run: { path: ".", PassThru: true } }))

      _(rendered).must_equal "@{\n'run' = @{\n'path' = '.'\n'PassThru' = $true\n}\n}"
    end

    it "indents nested keys relative to their depth" do
      rendered = verifier.send(:ps_hash, { outer: { inner: "value" } })

      # The outer key sits at depth 2, the inner one at depth 4.
      _(rendered).must_include "  'outer' = "
      _(rendered).must_include "    'inner' = 'value'"
    end

    it "doubles a single quote so it does not terminate the string early" do
      # Regression: values were concatenated between bare quotes, so an
      # apostrophe anywhere in the config broke the generated script.
      _(build_verifier.send(:ps_hash, "O'Brien")).must_equal "'O''Brien'"
    end

    it "escapes quotes in hash keys as well as values" do
      rendered = build_verifier.send(:ps_hash, { "it's" => "a 'quoted' value" })

      _(rendered).must_include "'it''s' = 'a ''quoted'' value'"
    end

    it "renders an empty hash" do
      _(squish(verifier.send(:ps_hash, {}))).must_equal "@{\n}"
    end
  end

  describe "#ps_environment" do
    it "escapes single quotes in values" do
      _(build_verifier.send(:ps_environment, { "MSG" => "it's here" }))
        .must_equal "$env:MSG = 'it''s here'"
    end

    it "returns an empty string when no environment variables are configured" do
      _(build_verifier.send(:ps_environment, {})).must_equal ""
    end

    it "emits one assignment per variable" do
      verifier = build_verifier

      _(verifier.send(:ps_environment, { "FOO" => "bar", "BAZ" => "qux" }))
        .must_equal "$env:FOO = 'bar'\n$env:BAZ = 'qux'"
    end
  end

  describe "#ps_single_quote" do
    it "quotes a plain string" do
      _(build_verifier.send(:ps_single_quote, "Stop")).must_equal "'Stop'"
    end

    it "doubles embedded single quotes" do
      _(build_verifier.send(:ps_single_quote, "it's")).must_equal "'it''s'"
    end

    it "handles a value that is only quotes" do
      # Two quotes in, each doubled, then wrapped: six quotes out.
      _(build_verifier.send(:ps_single_quote, "'" * 2)).must_equal("'" * 6)
    end

    it "leaves backslashes alone, since single-quoted strings do not escape them" do
      _(build_verifier.send(:ps_single_quote, 'C:\\path')).must_equal "'C:\\path'"
    end
  end

  describe "#pad" do
    it "defaults to no padding" do
      _(build_verifier.send(:pad)).must_equal ""
    end

    it "returns the requested number of spaces" do
      _(build_verifier.send(:pad, 4)).must_equal "    "
    end
  end

  describe "#shell_cmd" do
    it "uses powershell on Windows" do
      _(build_verifier.send(:shell_cmd)).must_equal "powershell"
    end

    it "uses pwsh on non-Windows platforms" do
      verifier = build_verifier({}, platform: PesterSpec::Helpers::UNIX_PLATFORM)

      _(verifier.send(:shell_cmd)).must_equal "pwsh"
    end

    it "prefixes sudo on non-Windows platforms when sudo is enabled" do
      verifier = build_verifier({ sudo: true }, platform: PesterSpec::Helpers::UNIX_PLATFORM)

      _(verifier.send(:shell_cmd)).must_equal "sudo pwsh"
    end

    it "honours an explicit shell over the platform default" do
      verifier = build_verifier({ shell: "pwsh-preview" })

      _(verifier.send(:shell_cmd)).must_equal "pwsh-preview"
    end

    it "combines an explicit shell with sudo" do
      verifier = build_verifier(
        { shell: "/usr/local/bin/pwsh", sudo: true },
        platform: PesterSpec::Helpers::UNIX_PLATFORM
      )

      _(verifier.send(:shell_cmd)).must_equal "sudo /usr/local/bin/pwsh"
    end

    it "ignores sudo on Windows even when the platform default is used" do
      # `sudo` is meaningless on Windows; the Windows branch never consults it.
      verifier = build_verifier({ sudo: true })

      _(verifier.send(:shell_cmd)).must_equal "powershell"
    end
  end

  describe "#use_local_powershell_modules" do
    it "prepends the sandbox modules folder to PSModulePath" do
      verifier = build_verifier({ root_path: "/tmp/verifier" })
      script = verifier.send(:use_local_powershell_modules, "Write-Host 'body'")

      _(script).must_include %{$PSModPathToPrepend = Join-Path "/tmp/verifier" -ChildPath 'modules'}
      _(script).must_include "$env:PSModulePath   = @($PSModPathToPrepend, $env:PSModulePath)"
    end

    it "embeds the supplied script" do
      _(build_verifier.send(:use_local_powershell_modules, "Write-Host 'body'"))
        .must_include "Write-Host 'body'"
    end

    it "silences the progress stream so WinRM output stays parseable" do
      _(build_verifier.send(:use_local_powershell_modules, ""))
        .must_include "$global:ProgressPreference = 'SilentlyContinue'"
    end

    it "does not create the modules folder on Linux, where it could be created as root" do
      _(build_verifier.send(:use_local_powershell_modules, ""))
        .must_include "if (!$isLinux -and -not (Test-Path -Path $PSModPathToPrepend))"
    end
  end

  describe "#really_wrap_shell_code" do
    it "dispatches to the Windows wrapper on Windows" do
      verifier = build_verifier
      verifier.expects(:really_wrap_windows_shell_code).with("body").returns("wrapped")

      _(verifier.send(:really_wrap_shell_code, "body")).must_equal "wrapped"
    end

    it "dispatches to the POSIX wrapper elsewhere" do
      verifier = build_verifier({}, platform: PesterSpec::Helpers::UNIX_PLATFORM)
      verifier.expects(:really_wrap_posix_shell_code).with("body").returns("wrapped")

      _(verifier.send(:really_wrap_shell_code, "body")).must_equal "wrapped"
    end
  end

  describe "#really_wrap_windows_shell_code" do
    let(:script) { build_verifier({ root_path: '$env:TEMP\\verifier' }).send(:really_wrap_windows_shell_code, "Write-Host 'body'") }

    it "writes the payload to kitchen_cmd.ps1 rather than passing it on the command line" do
      _(script).must_include "Set-Content -Path kitchen_cmd.ps1 -Encoding utf8 -Force"
    end

    it "relaxes the execution policy for the process only" do
      _(script).must_include "Set-ExecutionPolicy Unrestricted -Force -Scope Process"
    end

    it "invokes the generated script with the configured shell" do
      _(script).must_include "powershell ./kitchen_cmd.ps1"
    end

    it "includes the payload" do
      _(script).must_include "Write-Host 'body'"
    end
  end

  describe "#really_wrap_posix_shell_code" do
    let(:script) { build_verifier({ root_path: "/tmp/verifier" }, platform: PesterSpec::Helpers::UNIX_PLATFORM).send(:really_wrap_posix_shell_code, "Write-Host 'body'") }

    it "writes the payload via a quoted heredoc so the shell does not interpolate PowerShell variables" do
      _(script).must_include "cat << 'EOF' > kitchen_cmd.ps1"
    end

    it "adds a pwsh shebang" do
      _(script).must_include "#!/usr/bin/env pwsh"
    end

    it "makes the script executable and runs it" do
      _(script).must_include "chmod +x kitchen_cmd.ps1"
      _(script).must_include "pwsh ./kitchen_cmd.ps1"
    end

    it "creates the modules directory under the root path" do
      _(script).must_include "mkdir -p /tmp/verifier/modules"
    end
  end
end
