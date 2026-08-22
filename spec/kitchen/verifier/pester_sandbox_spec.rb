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

# Covers the parts of the verifier that touch the filesystem: assembling the
# sandbox that gets shipped to the SUT, and resolving the paths that results
# are downloaded back into. These run against real temporary directories --
# stubbing FileUtils here would only assert that the mocks were called.
describe Kitchen::Verifier::Pester do
  describe "#resolve_downloads_paths!" do
    it "resolves a relative remote source against the root path" do
      in_tmpdir do |dir|
        verifier = build_verifier({
          root_path: '$env:TEMP\\verifier',
          downloads: { "./PesterTestResults.xml" => File.join(dir, "results.xml") },
        })

        verifier.resolve_downloads_paths!

        source, = verifier.send(:config)[:downloads].first
        _(source).must_equal '$env:TEMP\\verifier/./PesterTestResults.xml'
      end
    end

    it "leaves a POSIX absolute remote source alone" do
      in_tmpdir do |dir|
        verifier = build_verifier({ downloads: { "/tmp/verifier/results.xml" => File.join(dir, "results.xml") } })

        verifier.resolve_downloads_paths!

        source, = verifier.send(:config)[:downloads].first
        _(source).must_equal "/tmp/verifier/results.xml"
      end
    end

    it "leaves a forward-slash Windows drive-letter remote source alone" do
      in_tmpdir do |dir|
        verifier = build_verifier({ downloads: { "C:/verifier/results.xml" => File.join(dir, "results.xml") } })

        verifier.resolve_downloads_paths!

        source, = verifier.send(:config)[:downloads].first
        _(source).must_equal "C:/verifier/results.xml"
      end
    end

    it "leaves a backslash-separated Windows path alone" do
      # Regression: the absolute-path test used to be the single-quoted string
      # '^/|^[a-zA-Z]:[\\/]'. Ruby collapses the doubled backslash before
      # Regexp.new sees it, leaving a class of just an escaped forward slash,
      # so a backslash never matched and C:\... was prefixed with root_path.
      in_tmpdir do |dir|
        verifier = build_verifier({
          root_path: "/tmp/verifier",
          downloads: { 'C:\\verifier\\results.xml' => File.join(dir, "results.xml") },
        })

        verifier.resolve_downloads_paths!

        source, = verifier.send(:config)[:downloads].first
        _(source).must_equal 'C:\\verifier\\results.xml'
      end
    end

    it "substitutes the instance name into the destination" do
      in_tmpdir do |dir|
        verifier = build_verifier({ downloads: { "./PesterTestResults.xml" => File.join(dir, "%{instance_name}", "results.xml") } })

        verifier.resolve_downloads_paths!

        _, destination = verifier.send(:config)[:downloads].first
        _(destination).must_equal File.join(dir, "pester-windows-2022", "results.xml")
      end
    end

    it "appends the source basename when the destination is a directory" do
      in_tmpdir do |dir|
        verifier = build_verifier({ downloads: { "./PesterTestResults.xml" => "#{dir}/testresults/" } })

        verifier.resolve_downloads_paths!

        _, destination = verifier.send(:config)[:downloads].first
        _(destination).must_equal File.join(dir, "testresults", "PesterTestResults.xml")
      end
    end

    it "treats a trailing backslash as a directory too" do
      # Regression: the directory test used to be the single-quoted string
      # '\\$|/$', which compiles to /\$|\/$/ -- "a literal dollar sign
      # anywhere, or a slash at the end" -- and so never matched a trailing
      # backslash despite the comment claiming it did.
      in_tmpdir do |dir|
        verifier = build_verifier({ downloads: { "./PesterTestResults.xml" => "#{dir}\\" } })

        verifier.resolve_downloads_paths!

        _, destination = verifier.send(:config)[:downloads].first
        _(destination).must_equal "#{dir}\\PesterTestResults.xml"
      end
    end

    it "does not mistake a dollar sign in the destination for a directory" do
      # Regression: the same faulty pattern matched '$' anywhere in the string,
      # so a destination like $env:TEMP/results.xml had its own basename
      # appended to it.
      in_tmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "out"))
        destination = File.join(dir, "out", "$results.xml")
        verifier = build_verifier({ downloads: { "./PesterTestResults.xml" => destination } })

        verifier.resolve_downloads_paths!

        _, resolved = verifier.send(:config)[:downloads].first
        _(resolved).must_equal destination
      end
    end

    it "takes the basename of a backslash-separated remote source" do
      # Regression: File.basename uses the workstation's separator rules, so on
      # macOS/Linux -- the usual place to drive a Windows SUT from -- the whole
      # 'C:\\...' string came back as the "basename" and became the local
      # filename.
      in_tmpdir do |dir|
        verifier = build_verifier({ downloads: { 'C:\\verifier\\results.xml' => "#{dir}/out/" } })

        verifier.resolve_downloads_paths!

        _, destination = verifier.send(:config)[:downloads].first
        _(destination).must_equal "#{dir}/out/results.xml"
      end
    end

    it "creates the local destination directory" do
      in_tmpdir do |dir|
        target = File.join(dir, "nested", "testresults")
        verifier = build_verifier({ downloads: { "./PesterTestResults.xml" => "#{target}/" } })

        verifier.resolve_downloads_paths!

        _(Dir.exist?(target)).must_equal true
      end
    end

    it "resolves every configured download" do
      in_tmpdir do |dir|
        verifier = build_verifier({
          downloads: {
            "./PesterTestResults.xml" => "#{dir}/results/",
            "./coverage.xml" => "#{dir}/coverage/",
          },
        })

        verifier.resolve_downloads_paths!

        _(verifier.send(:config)[:downloads].length).must_equal 2
      end
    end

    it "leaves :downloads a hash" do
      # Regression: this was a bare Hash#map, which returns an array of pairs,
      # so :downloads silently changed type once prepare_command had run.
      in_tmpdir do |dir|
        verifier = build_verifier({ downloads: { "./PesterTestResults.xml" => "#{dir}/out/" } })

        verifier.resolve_downloads_paths!

        _(verifier.send(:config)[:downloads]).must_be_kind_of Hash
        _(verifier.send(:config)[:downloads].keys).must_equal ["$env:TEMP\\verifier/./PesterTestResults.xml"]
      end
    end

    it "returns nil so it is never mistaken for the resolved list" do
      in_tmpdir do |dir|
        verifier = build_verifier({ downloads: { "./PesterTestResults.xml" => "#{dir}/results/" } })

        _(verifier.resolve_downloads_paths!).must_be_nil
      end
    end
  end

  describe "#remote_basename" do
    it "splits on forward slashes" do
      _(build_verifier.send(:remote_basename, "/tmp/verifier/results.xml")).must_equal "results.xml"
    end

    it "splits on backslashes regardless of the workstation platform" do
      _(build_verifier.send(:remote_basename, 'C:\\verifier\\results.xml')).must_equal "results.xml"
    end

    it "handles mixed separators" do
      _(build_verifier.send(:remote_basename, '$env:TEMP\\verifier/results.xml')).must_equal "results.xml"
    end

    it "returns a bare filename unchanged" do
      _(build_verifier.send(:remote_basename, "results.xml")).must_equal "results.xml"
    end

    it "returns an empty string for an empty path" do
      _(build_verifier.send(:remote_basename, "")).must_equal ""
    end
  end

  describe "#download_test_files" do
    it "downloads each configured pair over the transport connection" do
      in_tmpdir do |dir|
        verifier = build_verifier({ downloads: { "/remote/results.xml" => File.join(dir, "results.xml") } })
        connection = mock("connection")
        connection.expects(:download).with("/remote/results.xml", File.join(dir, "results.xml"))
        verifier.instance.transport.stubs(:connection).yields(connection)

        verifier.send(:download_test_files, {})
      end
    end

    it "does nothing when downloads are disabled" do
      verifier = build_verifier({ downloads: nil })
      verifier.instance.transport.expects(:connection).never

      verifier.send(:download_test_files, {})
    end
  end

  describe "#test_folder" do
    it "falls back to test_base_path when test_folder is unset" do
      verifier = build_verifier({ test_folder: nil, test_base_path: "/kitchen/test/integration" })

      _(verifier.send(:test_folder)).must_equal "/kitchen/test/integration"
    end

    it "descends into an integration subfolder when one exists" do
      in_tmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "integration"))
        verifier = build_verifier({ test_folder: dir })

        _(verifier.send(:test_folder)).must_equal File.join(File.realpath(dir), "integration")
      end
    end

    it "uses the folder itself when there is no integration subfolder" do
      # Both branches return a String. The no-integration branch used to leak
      # the Pathname built by #realpath, so #test_folder's return type depended
      # on the layout of the directory it was pointed at.
      in_tmpdir do |dir|
        verifier = build_verifier({ test_folder: dir })

        _(verifier.send(:test_folder)).must_equal File.realpath(dir)
        _(verifier.send(:test_folder)).must_be_kind_of String
      end
    end
  end

  describe "#suite_test_folder" do
    it "joins the suite name onto the test folder" do
      in_tmpdir do |dir|
        verifier = build_verifier({ test_folder: dir }, suite_name: "smoke")

        _(verifier.send(:suite_test_folder)).must_equal File.join(File.realpath(dir), "smoke")
      end
    end
  end

  describe "#support_psmodule_folder" do
    it "points at the PesterUtil module shipped with the gem" do
      path = build_verifier.send(:support_psmodule_folder).to_s

      _(path).must_match(%r{support/modules/PesterUtil\z})
      _(File.exist?(File.join(path, "PesterUtil.psm1"))).must_equal true
    end
  end

  describe "#copy_if_src_exists" do
    it "copies the source folder into the destination" do
      in_tmpdir do |dir|
        src = File.join(dir, "suites")
        dest = File.join(dir, "sandbox")
        FileUtils.mkdir_p(src)
        File.write(File.join(src, "default.tests.ps1"), "Describe 'x' {}")

        build_verifier.send(:copy_if_src_exists, src, dest)

        _(File.exist?(File.join(dest, "suites", "default.tests.ps1"))).must_equal true
      end
    end

    it "creates the destination when it does not exist" do
      in_tmpdir do |dir|
        src = File.join(dir, "suites")
        dest = File.join(dir, "deeply", "nested", "sandbox")
        FileUtils.mkdir_p(src)

        build_verifier.send(:copy_if_src_exists, src, dest)

        _(Dir.exist?(dest)).must_equal true
      end
    end

    it "does nothing when the source is missing" do
      in_tmpdir do |dir|
        dest = File.join(dir, "sandbox")

        build_verifier.send(:copy_if_src_exists, File.join(dir, "absent"), dest)

        _(Dir.exist?(dest)).must_equal false
      end
    end
  end

  describe "#helper_files" do
    it "returns files nested under the helpers folder, excluding directories" do
      in_tmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "helpers", "shared", "nested"))
        File.write(File.join(dir, "helpers", "shared", "helper.ps1"), "")
        File.write(File.join(dir, "helpers", "shared", "nested", "deep.ps1"), "")
        verifier = build_verifier({ test_folder: dir })

        found = verifier.send(:helper_files).map { |f| File.basename(f) }.sort

        _(found).must_equal %w{deep.ps1 helper.ps1}
      end
    end

    it "returns an empty list when there is no helpers folder" do
      in_tmpdir do |dir|
        _(build_verifier({ test_folder: dir }).send(:helper_files)).must_equal []
      end
    end
  end

  describe "#prepare_helpers" do
    it "copies helpers into the sandbox, stripping the helpers prefix" do
      in_tmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "helpers", "shared"))
        File.write(File.join(dir, "helpers", "shared", "helper.ps1"), "function Get-Thing {}")
        verifier = build_verifier({ test_folder: dir })
        sandbox = File.join(dir, "sandbox")
        verifier.stubs(:sandbox_path).returns(sandbox)

        verifier.send(:prepare_helpers)

        _(File.read(File.join(sandbox, "shared", "helper.ps1"))).must_equal "function Get-Thing {}"
      end
    end
  end

  describe "#prepare_copy_folders" do
    it "copies each configured folder into the sandbox modules folder" do
      in_tmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "src", "MyModule"))
        File.write(File.join(dir, "src", "MyModule", "MyModule.psm1"), "")
        verifier = build_verifier({ kitchen_root: dir, copy_folders: ["src/MyModule"] })
        sandbox = File.join(dir, "sandbox")
        verifier.stubs(:sandbox_path).returns(sandbox)

        verifier.send(:prepare_copy_folders)

        _(File.exist?(File.join(sandbox, "modules", "MyModule", "MyModule.psm1"))).must_equal true
      end
    end

    it "does nothing when copy_folders is nil" do
      verifier = build_verifier({ copy_folders: nil })
      verifier.expects(:copy_if_src_exists).never

      verifier.send(:prepare_copy_folders)
    end
  end

  describe "#list_files" do
    it "lists files at the top level and nested beneath it" do
      in_tmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "nested", "deeper"))
        File.write(File.join(dir, "top.ps1"), "")
        File.write(File.join(dir, "nested", "deeper", "bottom.ps1"), "")

        found = build_verifier.send(:list_files, dir).map { |f| File.basename(f) }

        _(found).must_include "top.ps1"
        _(found).must_include "bottom.ps1"
      end
    end
  end

  describe "#create_sandbox" do
    it "stages the PesterUtil module, the suite tests and the helpers" do
      in_tmpdir do |dir|
        suite = File.join(dir, "integration", "pester")
        FileUtils.mkdir_p(suite)
        File.write(File.join(suite, "default.tests.ps1"), "Describe 'x' {}")
        FileUtils.mkdir_p(File.join(dir, "integration", "helpers", "shared"))
        File.write(File.join(dir, "integration", "helpers", "shared", "helper.ps1"), "")

        verifier = build_verifier({ test_folder: dir, kitchen_root: dir })
        begin
          verifier.create_sandbox
          sandbox = verifier.sandbox_path

          _(File.exist?(File.join(sandbox, "modules", "PesterUtil", "PesterUtil.psm1"))).must_equal true
          _(File.exist?(File.join(sandbox, "suites", "pester", "default.tests.ps1"))).must_equal true
          _(File.exist?(File.join(sandbox, "shared", "helper.ps1"))).must_equal true
        ensure
          verifier.cleanup_sandbox
        end
      end
    end
  end
end
