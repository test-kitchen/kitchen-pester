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

# Covers the fragments that bootstrap Pester and its dependencies on the SUT.
# Each of these returns nil (rather than an empty string) when its feature is
# switched off, and #install_command_script relies on that to decide what to
# splice together.
describe Kitchen::Verifier::Pester do
  describe "#install_pester" do
    it "returns nil when the install is skipped" do
      _(build_verifier({ skip_pester_install: true }).install_pester).must_be_nil
    end

    it "trusts the PSGallery before installing" do
      _(build_verifier.install_pester)
        .must_include "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted"
    end

    it "splats the default install parameters" do
      script = build_verifier.install_pester

      _(script).must_include "'SkipPublisherCheck' = $true"
      _(script).must_include "'Force' = $true"
      _(script).must_include "'ErrorAction' = 'Stop'"
      _(script).must_include "Install-module @installPesterParams"
    end

    it "always sets the module name to Pester" do
      _(build_verifier.install_pester).must_include "$installPesterParams['Name'] = 'Pester'"
    end

    it "honours overridden install parameters" do
      script = build_verifier({ pester_install: { MaximumVersion: "4.10.1" } }).install_pester

      _(script).must_include "'MaximumVersion' = '4.10.1'"
      _(script).wont_include "SkipPublisherCheck"
    end

    it "still names the module when pester_install is explicitly nil" do
      script = build_verifier({ pester_install: nil }).install_pester

      _(script).must_include "$installPesterParams['Name'] = 'Pester'"
    end
  end

  describe "#install_modules_from_gallery" do
    it "returns nil when install_modules is nil" do
      _(build_verifier({ install_modules: nil }).install_modules_from_gallery).must_be_nil
    end

    it "returns an empty list when nothing is configured" do
      _(build_verifier.install_modules_from_gallery).must_equal []
    end

    it "installs a bare module name by name" do
      scripts = build_verifier({ install_modules: ["PSScriptAnalyzer"] }).install_modules_from_gallery

      _(scripts.length).must_equal 1
      _(scripts.first).must_include "Install-Module -Name 'PSScriptAnalyzer'"
    end

    it "splats a hash module so extra parameters are honoured" do
      scripts = build_verifier({ install_modules: [{ Name: "Pester", RequiredVersion: "5.5.0" }] })
        .install_modules_from_gallery

      _(scripts.first).must_include "'Name' = 'Pester'"
      _(scripts.first).must_include "'RequiredVersion' = '5.5.0'"
      _(scripts.first).must_include "Install-Module @Pester"
    end

    it "sanitizes module names that are not valid PowerShell variable names" do
      # $powershell-yaml would parse as a subtraction, so the variable is
      # renamed while the module name itself is left intact.
      scripts = build_verifier({ install_modules: [{ Name: "powershell-yaml" }] })
        .install_modules_from_gallery

      _(scripts.first).must_include "$powershell_yaml = "
      _(scripts.first).must_include "Install-Module @powershell_yaml"
      _(scripts.first).must_include "'Name' = 'powershell-yaml'"
    end

    it "handles a mix of string and hash entries" do
      scripts = build_verifier({ install_modules: ["PSScriptAnalyzer", { Name: "Pester" }] })
        .install_modules_from_gallery

      _(scripts.length).must_equal 2
    end
  end

  describe "#get_powershell_modules_from_nugetapi" do
    it "returns nil when bootstrap has no modules key" do
      _(build_verifier({ bootstrap: {} }).get_powershell_modules_from_nugetapi).must_be_nil
    end

    it "returns nil when bootstrap itself is nil" do
      _(build_verifier({ bootstrap: nil }).get_powershell_modules_from_nugetapi).must_be_nil
    end

    it "returns an empty list for the default empty module list" do
      _(build_verifier.get_powershell_modules_from_nugetapi).must_equal []
    end

    it "passes the configured gallery url" do
      scripts = build_verifier({ bootstrap: { repository_url: "https://www.powershellgallery.com/api/v2", modules: ["PackageManagement"] } })
        .get_powershell_modules_from_nugetapi

      _(scripts.first).must_include "-GalleryUrl 'https://www.powershellgallery.com/api/v2'"
    end

    it "does not deep-merge the bootstrap defaults" do
      # default_config replaces a key wholesale rather than merging into it, so
      # supplying only :modules drops the default :repository_url and
      # -GalleryUrl is omitted. Install-ModuleFromNuget then falls back to its
      # own default, which happens to be the same URL -- but a config that
      # overrides :repository_url elsewhere would lose it here.
      scripts = build_verifier({ bootstrap: { modules: ["PackageManagement"] } })
        .get_powershell_modules_from_nugetapi

      _(scripts.first).wont_include "-GalleryUrl"
    end

    it "passes a custom repository url" do
      scripts = build_verifier({ bootstrap: { repository_url: "https://proget.example/nuget/psgallery", modules: ["PowerShellGet"] } })
        .get_powershell_modules_from_nugetapi

      _(scripts.first).must_include "-GalleryUrl 'https://proget.example/nuget/psgallery'"
    end

    it "omits the gallery parameter when no repository url is set" do
      scripts = build_verifier({ bootstrap: { repository_url: nil, modules: ["PowerShellGet"] } })
        .get_powershell_modules_from_nugetapi

      _(scripts.first).wont_include "-GalleryUrl"
    end

    it "wraps a bare module name in a hashtable" do
      scripts = build_verifier({ bootstrap: { modules: ["PowerShellGet"] } })
        .get_powershell_modules_from_nugetapi

      _(scripts.first).must_include "Install-ModuleFromNuget -Module @{Name = 'PowerShellGet'}"
    end

    it "assigns a hash module to a variable named after the module" do
      scripts = build_verifier({ bootstrap: { modules: [{ Name: "PowerShellGet", Version: "2.2.5" }] } })
        .get_powershell_modules_from_nugetapi

      _(scripts.first).must_include "${PowerShellGet} = "
      _(scripts.first).must_include "'Version' = '2.2.5'"
      _(scripts.first).must_include "Install-ModuleFromNuget -Module ${PowerShellGet}"
    end
  end

  describe "#register_psrepository_scriptblock" do
    it "returns nil when register_repository is nil" do
      _(build_verifier({ register_repository: nil }).register_psrepository_scriptblock).must_be_nil
    end

    it "returns an empty list when nothing is configured" do
      _(build_verifier.register_psrepository_scriptblock).must_equal []
    end

    it "emits a Set-PSRepo call per repository" do
      scripts = build_verifier({
        register_repository: [
          { Name: "Internal", SourceLocation: "https://proget.example/nuget/internal" },
          { Name: "Partners", SourceLocation: "https://proget.example/nuget/partners" },
        ],
      }).register_psrepository_scriptblock

      _(scripts.length).must_equal 2
      _(scripts.first).must_include "${Internal} = "
      _(scripts.first).must_include "Set-PSRepo -Repository ${Internal}"
      _(scripts.last).must_include "Set-PSRepo -Repository ${Partners}"
    end

    it "renders every key of the repository definition" do
      scripts = build_verifier({
        register_repository: [{ Name: "Internal", SourceLocation: "https://proget.example/nuget", InstallationPolicy: "Trusted" }],
      }).register_psrepository_scriptblock

      _(scripts.first).must_include "'SourceLocation' = 'https://proget.example/nuget'"
      _(scripts.first).must_include "'InstallationPolicy' = 'Trusted'"
    end
  end

  describe "#install_command_script" do
    it "imports PesterUtil, which supplies Install-ModuleFromNuget and Set-PSRepo" do
      _(build_verifier.install_command_script).must_include "Import-Module -ErrorAction Stop PesterUtil"
    end

    it "composes every enabled bootstrap step" do
      script = build_verifier({
        bootstrap: { modules: ["PowerShellGet"] },
        register_repository: [{ Name: "Internal" }],
        install_modules: ["PSScriptAnalyzer"],
      }).install_command_script

      _(script).must_include "Install-ModuleFromNuget"
      _(script).must_include "Set-PSRepo -Repository ${Internal}"
      _(script).must_include "Install-module @installPesterParams"
      _(script).must_include "Install-Module -Name 'PSScriptAnalyzer'"
    end

    it "omits the Pester install when it is skipped" do
      script = build_verifier({ skip_pester_install: true }).install_command_script

      _(script).wont_include "Install-module @installPesterParams"
    end

    it "survives every optional section being nil" do
      script = build_verifier({ bootstrap: nil, register_repository: nil, install_modules: nil })
        .install_command_script

      _(script).must_include "Import-Module -ErrorAction Stop PesterUtil"
    end
  end

  describe "#install_command" do
    it "removes the in-box PowerShellGet and PackageManagement by default" do
      script = build_verifier.install_command

      _(script).must_include "ModuleName = 'PackageManagement'; RequiredVersion = '1.0.0.1'"
      _(script).must_include "ModuleName = 'PowerShellGet'; RequiredVersion = '1.0.0.1'"
    end

    it "removes the in-box Pester 3.4.0 by default" do
      _(build_verifier.install_command).must_include "ModuleName = 'Pester'; RequiredVersion = '3.4.0'"
    end

    it "guards the removals behind the config flags" do
      script = build_verifier({ remove_builtin_powershellget: false, remove_builtin_pester: false }).install_command

      _(script).must_include "if ($false) {"
      _(script).wont_include "if ($true) {"
    end

    it "returns early when there is nothing to remove, as on PowerShell 7 for Linux" do
      _(build_verifier.install_command).must_include "if ($modulesToRemove.ModuleBase.Count -eq 0)"
    end
  end
end
