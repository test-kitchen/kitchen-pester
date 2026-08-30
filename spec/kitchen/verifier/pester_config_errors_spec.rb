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

# Covers what happens when kitchen.yml is wrong rather than when it is right.
#
# Every option below is documented as a list of mappings or as a mapping with a
# Name, and YAML makes all of them easy to get subtly wrong -- a missing `- `,
# a forgotten key, a value left blank. The verifier interpolates these straight
# into PowerShell, so an unchecked mistake either raises somewhere unrelated in
# Ruby or ships a broken script to the instance and fails there. These specs
# pin the messages that say which option is at fault.
describe Kitchen::Verifier::Pester do
  describe "a list option given as a single mapping" do
    it "rejects install_modules" do
      verifier = build_verifier({ install_modules: { Name: "PSScriptAnalyzer" } })

      error = _ { verifier.install_modules_from_gallery }.must_raise Kitchen::UserError
      _(error.message).must_include "'install_modules' must be a list"
      _(error.message).must_include "Put a '- ' in front of each entry"
    end

    it "rejects register_repository" do
      verifier = build_verifier({ register_repository: { Name: "MyRepo", SourceLocation: "https://example.test/api/v2" } })

      error = _ { verifier.register_psrepository_scriptblock }.must_raise Kitchen::UserError
      _(error.message).must_include "'register_repository' must be a list"
    end

    it "rejects bootstrap.modules" do
      verifier = build_verifier({ bootstrap: { repository_url: "https://example.test/api/v2", modules: { Name: "PowerShellGet" } } })

      error = _ { verifier.get_powershell_modules_from_nugetapi }.must_raise Kitchen::UserError
      _(error.message).must_include "'bootstrap.modules' must be a list"
    end

    it "rejects copy_folders" do
      verifier = build_verifier({ copy_folders: { output: "MyModule" }, kitchen_root: "/kitchen" })
      verifier.stubs(:sandbox_path).returns("/kitchen/sandbox")

      error = _ { verifier.send(:prepare_copy_folders) }.must_raise Kitchen::UserError
      _(error.message).must_include "'copy_folders' must be a list"
    end

    it "still accepts a list, which is the documented shape" do
      verifier = build_verifier({ install_modules: [{ Name: "PSScriptAnalyzer" }] })

      _(verifier.install_modules_from_gallery.first).must_include "Install-Module @PSScriptAnalyzer"
    end

    it "still accepts a bare string entry" do
      verifier = build_verifier({ install_modules: %w{PSScriptAnalyzer} })

      _(verifier.install_modules_from_gallery.first).must_include "Install-Module -Name 'PSScriptAnalyzer'"
    end
  end

  describe "a mapping entry with no Name" do
    it "rejects an install_modules entry" do
      verifier = build_verifier({ install_modules: [{ Repository: "MyRepo" }] })

      error = _ { verifier.install_modules_from_gallery }.must_raise Kitchen::UserError
      _(error.message).must_include "'install_modules' needs a 'Name'"
      _(error.message).must_include "Repository"
    end

    it "rejects a register_repository entry" do
      verifier = build_verifier({ register_repository: [{ SourceLocation: "https://example.test/api/v2" }] })

      error = _ { verifier.register_psrepository_scriptblock }.must_raise Kitchen::UserError
      _(error.message).must_include "'register_repository' needs a 'Name'"
    end

    it "rejects a bootstrap.modules entry" do
      verifier = build_verifier({ bootstrap: { repository_url: "https://example.test/api/v2", modules: [{ Version: "2.2.5" }] } })

      error = _ { verifier.get_powershell_modules_from_nugetapi }.must_raise Kitchen::UserError
      _(error.message).must_include "'bootstrap.modules' needs a 'Name'"
    end

    it "rejects a Name that is present but empty" do
      verifier = build_verifier({ install_modules: [{ Name: "" }] })

      _ { verifier.install_modules_from_gallery }.must_raise Kitchen::UserError
    end

    it "rejects a register_repository entry that is a bare string, since it is splatted" do
      verifier = build_verifier({ register_repository: %w{MyRepo} })

      error = _ { verifier.register_psrepository_scriptblock }.must_raise Kitchen::UserError
      _(error.message).must_include "must be a mapping"
    end

    it "accepts a string key, since not every config path symbolizes keys" do
      verifier = build_verifier({ install_modules: [{ "Name" => "PSScriptAnalyzer" }] })

      _(verifier.install_modules_from_gallery.first).must_include "Install-Module @PSScriptAnalyzer"
    end
  end

  describe "a test_folder that does not exist" do
    it "names the option and the path instead of raising Errno::ENOENT" do
      verifier = build_verifier({ test_folder: "definitely/not/here" })

      error = _ { verifier.send(:test_folder) }.must_raise Kitchen::UserError
      _(error.message).must_include "'test_folder'"
      _(error.message).must_include "definitely/not/here"
      _(error.message).must_include "does not exist"
    end

    it "surfaces through create_sandbox, where the folder is first read" do
      verifier = build_verifier({ test_folder: "definitely/not/here" })

      _ { verifier.create_sandbox }.must_raise Kitchen::UserError
    end
  end

  describe "a downloads entry with no destination" do
    it "names the source it belongs to" do
      verifier = build_verifier({ downloads: { "PesterTestResults.xml" => nil }, root_path: "/tmp/verifier" })

      error = _ { verifier.resolve_downloads_paths! }.must_raise Kitchen::UserError
      _(error.message).must_include "has no local destination"
      _(error.message).must_include "PesterTestResults.xml"
    end
  end
end
