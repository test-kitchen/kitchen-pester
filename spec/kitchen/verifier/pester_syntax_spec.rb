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

# The verifier's whole output is PowerShell source that will be parsed on the
# SUT, several minutes and one VM boot away from here. These specs run the
# generated scripts through the real PowerShell parser so that a quoting or
# brace bug fails in milliseconds instead of during `kitchen verify`.
#
# They skip when pwsh is not on PATH, so the suite stays runnable on a bare
# Ruby box; CI installs pwsh to get the coverage.
describe "generated PowerShell" do
  # Config chosen to exercise the awkward paths: nested hashtables, arrays,
  # booleans, a module name that is not a valid variable name, and apostrophes
  # in both keys and values.
  HOSTILE_CONFIG = {
    root_path: '$env:TEMP\\verifier',
    environment: { "MSG" => "it's here", "QUOTED" => "a 'quoted' value" },
    bootstrap: {
      repository_url: "https://example.test/api/v2",
      modules: ["PowerShellGet", { Name: "Pester", Version: "5.5.0", Force: true }],
    },
    register_repository: [{ Name: "Internal", SourceLocation: "https://example.test/nuget", InstallationPolicy: "Trusted" }],
    install_modules: ["PSScriptAnalyzer", { Name: "powershell-yaml", RequiredVersion: "0.4.7" }],
    pester_install: { SkipPublisherCheck: true, Force: true, ErrorAction: "Stop" },
    pester_configuration: {
      run: { path: ".", PassThru: true, Exclude: %w{slow flaky} },
      Filter: { ExcludeTag: ["needs'quote"] },
      Output: { Verbosity: "Detailed" },
    },
  }.freeze

  # Parses source with System.Management.Automation.Language.Parser.
  #
  # @param source [String] PowerShell source
  # @return [Array<String>] parser error messages, empty when the source parses
  def parse_errors(source)
    Dir.mktmpdir("kitchen-pester-syntax-") do |dir|
      path = File.join(dir, "generated.ps1")
      File.write(path, source)
      command = <<~PS
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile('#{path}', [ref]$null, [ref]$errors)
        $errors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }
      PS
      IO.popen(["pwsh", "-NoProfile", "-NonInteractive", "-Command", command], err: %i{child out}, &:read)
        .to_s.lines.map(&:chomp).reject(&:empty?)
    end
  end

  before do
    skip "pwsh is not installed" unless PesterSpec::Helpers.pwsh?
  end

  %i{install_command install_command_script invoke_pester_scriptblock init_command}.each do |generator|
    it "emits parseable PowerShell from ##{generator}" do
      verifier = build_verifier(HOSTILE_CONFIG.merge(restart_winrm: true))
      errors = parse_errors(verifier.public_send(generator).to_s)

      _(errors).must_equal [], "##{generator} generated PowerShell that does not parse:\n  #{errors.join("\n  ")}"
    end
  end

  it "keeps an apostrophe inside the string it belongs to" do
    verifier = build_verifier({ environment: { "MSG" => "it's here" } })

    _(parse_errors(verifier.invoke_pester_scriptblock)).must_equal []
  end

  it "would have caught an unescaped apostrophe" do
    # Guards the guard: prove the parser check actually fails on the bug it
    # exists to catch, rather than silently passing everything.
    _(parse_errors("$env:MSG = 'it's here'")).wont_be_empty
  end
end
