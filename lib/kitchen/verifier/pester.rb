# -*- encoding: utf-8 -*-
#
# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
# Copyright (C) 2015, Steven Murawski
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "fileutils"
require "pathname"
require "kitchen/util"
require "kitchen/verifier/base"
require "kitchen/version"
require_relative "pester_version"

module Kitchen

  module Verifier

    class Pester < Kitchen::Verifier::Base

      kitchen_verifier_api_version 1

      plugin_version Kitchen::Verifier::PESTER_VERSION

      default_config :restart_winrm, false
      default_config :test_folder
      # I want to add a way to copy modules from local to remote.
      # most modern pipelines I see saves the modules needed locally, per project,
      # and use those required modules in the build for, say, unit tests and other.
      # easiest way and most flexible I can think of is to copy a list of folders to
      # the SUT, and maybe add a way to add it to the PSModulePath
      default_config :use_local_pester_module, false
      default_config :unzip_psmodule_from_nugetapi, [
        {"ModuleName" => "PowerShellGet"},
        {"ModuleName" => "PackageManagement"}
      ]
      default_config :psrepository_to_register
      default_config :modules_from_gallery, []
      default_config :pester_install_param, {"Name" => "Pester", "RequiredVersion" => "4.10.1", "Force" => true }
      default_config :nuget_uri, "https://www.powershellgallery.com/api/v2"
      default_config :downloads, ["./PesterTestResults.xml"] => "./testresults"

      # Creates a new Verifier object using the provided configuration data
      # which will be merged with any default configuration.
      #
      # @param config [Hash] provided verifier configuration
      def initialize(config = {})
        init_config(config)
      end

      # Creates a temporary directory on the local workstation into which
      # verifier related files and directories can be copied or created. The
      # contents of this directory will be copied over to the instance before
      # invoking the verifier's run command. After this method completes, it
      # is expected that the contents of the sandbox is complete and ready for
      # copy to the remote instance.
      #
      # **Note:** any subclasses would be well advised to call super first when
      # overriding this method, for example:
      #
      # @example overriding `#create_sandbox`
      #
      #   class MyVerifier < Kitchen::Verifier::Base
      #     def create_sandbox
      #       super
      #       # any further file copies, preparations, etc.
      #     end
      #   end
      def create_sandbox
        super
        prepare_powershell_modules
        prepare_pester_tests
        prepare_helpers
      end

      def register_psrepository
        return if config[:psrepository_to_register].nil?

        info("Registering a new PowerShellGet Repository")
        # "register-packagesource -providername PowerShellGet -name '#{psmodule_repository_name}' -location '#{config[:gallery_uri]}' -force -trusted"
      end

      # Generates a command string which will install and configure the
      # verifier software on an instance. If no work is required, then `nil`
      # will be returned.
      #
      # @return [String] a command string
      def install_command; end 
      # PowerShellGet & Pester Bootstrap are done in prepare_command (after sandbox is transferred)

      # Generates a command string which will perform any data initialization
      # or configuration required after the verifier software is installed
      # but before the sandbox has been transferred to the instance. If no work
      # is required, then `nil` will be returned.
      #
      # @return [String] a command string
      def init_command
        restart_winrm_service if config[:restart_winrm]
      end

      # Generates a command string which will perform any commands or
      # configuration required just before the main verifier run command but
      # after the sandbox has been transferred to the instance. If no work is
      # required, then `nil` will be returned.
      #
      # @return [String] a command string
      def prepare_command
        return if local_suite_files.empty?
        return if config[:use_local_pester_module]

        really_wrap_shell_code(install_command_script)
      end

      # Generates a command string which will invoke the main verifier
      # command on the prepared instance. If no work is required, then `nil`
      # will be returned.
      #
      # @return [String] a command string
      def run_command
        return if local_suite_files.empty?

        really_wrap_shell_code(run_command_script)
      end

      # Download functionality was added to the base verifier behavior after
      # version 2.3.4
      if Gem::Version.new(Kitchen::VERSION) <= Gem::Version.new("2.3.4")
        def call(state)
          super
        ensure
          download_test_files(state)
        end
      else
        def call(state)
          super
        rescue
          # If the verifier reports failure, we need to download the files ourselves.
          # Test Kitchen's base verifier doesn't have the download in an `ensure` block.
          download_test_files(state)

          # Rethrow original exception, we still want to register the failure.
          raise
        end
      end

      # private
      def run_command_script
        <<-CMD
          Import-Module -Name Pester -Force

          $TestPath = Join-Path "#{config[:root_path]}" -ChildPath "suites"
          $OutputFilePath = Join-Path "#{config[:root_path]}" -ChildPath 'PesterTestResults.xml'

          $options = New-PesterOption -TestSuiteName "Pester - #{instance.to_str}"

          $result = Invoke-Pester -Script $TestPath -OutputFile $OutputFilePath -OutputFormat NUnitXml -PesterOption $options -PassThru
          $result | Export-CliXml -Path (Join-Path -Path $TestPath -ChildPath 'result.xml')

          $LASTEXITCODE = $result.FailedCount
          $host.SetShouldExit($LASTEXITCODE)

          exit $LASTEXITCODE
        CMD
      end

      def get_powershell_modules_from_nugetapi
        
        Array(config[:unzip_psmodule_from_nugetapi]).map do |powershell_module|
          if powershell_module.is_a? Hash
            <<-PSCode
              ${#{powershell_module[:ModuleName]}} = #{ps_hash(powershell_module)}
              Install-ModuleFromNuget -Module ${#{powershell_module[:ModuleName]}} -GalleryUrl '#{config[:nuget_uri]}'
            PSCode
          else
            "Install-ModuleFromNuget -Module @{ModuleName = '#{powershell_module}'} -GalleryUrl '#{config[:nuget_uri]}'"
          end
        end
      end

      def install_pester
        <<-PSCode
        Write-Host "Installing Pester"
        $InstallPesterParams = #{ps_hash(config[:pester_install_param])}
        Install-module @InstallPesterParams

        PSCode
      end

      def register_psrepositories
        "Write-Host 'Registering PS Repositories not yet implemented'"
      end

      def install_modules_from_gallery
        "Write-host 'Instaling modules from gallery not yet implemented'"
      end
      
      def really_wrap_shell_code(code)
        # hypothesis: if OS not windows (can we detect or assume from transport)
        # write the wrapped shell code to file with the pwsh(-preview) shebang
        # and execute the file
        # leave as is for windows (but double check we can use pwsh & pwsh-preview too)
        wrap_shell_code(Util.outdent!(use_local_powershell_modules(code)))
      end

      def use_local_powershell_modules(script)
        <<-EOH
          try {
              Set-ExecutionPolicy Unrestricted -force
          }
          catch {
              $_ | Out-String | Write-Warning
          }

          $global:ProgressPreference = 'SilentlyContinue'
          $PSModPathToPrepend = Join-Path "#{config[:root_path]}" -ChildPath 'modules'
          if ($Env:PSModulePath.Split([io.path]::PathSeparator) -notcontains $PSModPathToPrepend) {
            $env:PSModulePath   = @($PSModPathToPrepend, $env:PSModulePath) -Join [io.path]::PathSeparator
          }

          #{script}
        EOH
      end

      def install_command_script
        <<-EOH
          $PowerShellGet = @{ModuleName = 'PowerShellGet'; ModuleVersion = '2.2.4.1';}
          $PackageManagement = @{ModuleName = 'PackageManagement'; ModuleVersion = '1.4.7';}
          $GalleryUrl = '#{config[:nuget_uri]}'
          #{get_powershell_modules_from_nugetapi.join("\n")}
          #{install_pester}
          #{register_psrepositories}
          #{install_modules_from_gallery}
        EOH
      end

      def restart_winrm_service
        cmd = "schtasks /Create /TN restart_winrm /TR " \
              '"powershell -Command Restart-Service winrm" ' \
              "/SC ONCE /ST 00:00 "
        wrap_shell_code(Util.outdent!(<<-CMD
          #{cmd}
          schtasks /RUN /TN restart_winrm
        CMD
                                     ))
      end

      def download_test_files(state)
        info("Downloading test result files from #{instance.to_str}")

        instance.transport.connection(state) do |conn|
          config[:downloads].to_h.each do |remotes, local|
            debug("Downloading #{Array(remotes).join(", ")} to #{local}")
            conn.download(remotes, local)
          end
        end

        debug("Finished downloading test result files from #{instance.to_str}")
      end

      # Returns an Array of test suite filenames for the related suite currently
      # residing on the local workstation. Any special provisioner-specific
      # directories (such as a Chef roles/ directory) are excluded.
      #
      # @return [Array<String>] array of suite files
      # @api private
      def suite_test_folder
        @suite_test_folder ||= File.join(test_folder, config[:suite_name])
      end

      # @api private
      def suite_level_glob
        Dir.glob(File.join(suite_test_folder, "*"))
      end

      # @api private
      def suite_verifier_level_glob
        Dir.glob(File.join(suite_test_folder, "*/**/*"))
      end

      # @api private
      def local_suite_files
        suite = suite_level_glob
        suite_verifier = suite_verifier_level_glob
        (suite << suite_verifier).flatten!.reject do |f|
          File.directory?(f)
        end
      end

      # @api private
      def sandboxify_path(path)
        File.join(sandbox_path, "suites", path.sub(%r{#{suite_test_folder}/}i, ""))
      end

      # Returns an Array of common helper filenames currently residing on the
      # local workstation.
      #
      # @return [Array<String>] array of helper files
      # @api private
      def helper_files
        glob = Dir.glob(File.join(test_folder, "helpers", "*/**/*"))
        glob.reject { |f| File.directory?(f) }
      end

      # Copies all common testing helper files into the suites directory in
      # the sandbox.
      #
      # @api private
      def prepare_helpers
        base = File.join(test_folder, "helpers")

        helper_files.each do |src|
          dest = File.join(sandbox_path, src.sub("#{base}/", ""))
          debug("Copying #{src} to #{dest}")
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest, preserve: true)
        end
      end

      # Creates a PowerShell hashtable from an ruby map.
      # The only types supported for now are hash, string and Boolean.
      #
      # @api private
      def ps_hash(obj, depth = 0)
        if [true, false].include? obj
          %{$#{obj}}
        elsif obj.is_a?(Hash)
          obj.map do |k, v|
            %{#{pad(depth + 2)}#{ps_hash(k)} = #{ps_hash(v, depth + 2)}}
          end.join(";\n").insert(0, "@{\n").insert(-1, "\n#{pad(depth)}}")
        elsif obj.is_a?(Array)
          array_string = obj.map { |v| ps_hash(v, depth + 4) }.join(",")
          "#{pad(depth)}@(\n#{array_string}\n)"
        else
          %{"#{obj}"}
        end
      end

      # Copies all test suite files into the suites directory in the sandbox.
      #
      # @api private
      def prepare_pester_tests
        info("Preparing to copy files from #{suite_test_folder} to the SUT.")

        local_suite_files.each do |src|
          dest = sandboxify_path(src)
          debug("Copying #{src} to #{dest}")
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest, preserve: true)
        end
      end

      def prepare_powershell_module(name)
        FileUtils.mkdir_p(File.join(sandbox_path, "modules/#{name}"))
        FileUtils.cp(
          File.join(File.dirname(__FILE__), "../../support/powershell/#{name}/#{name}.psm1"),
          File.join(sandbox_path, "modules/#{name}/#{name}.psm1"),
          preserve: true
        )
      end

      def prepare_powershell_modules
        info("Preparing to copy supporting powershell modules.")
        %w{PesterUtil}.each do |module_name|
          prepare_powershell_module module_name
        end
      end

      def test_folder
        return config[:test_base_path] if config[:test_folder].nil?

        absolute_test_folder
      end

      def absolute_test_folder
        path = (Pathname.new config[:test_folder]).realpath
        integration_path = File.join(path, "integration")
        return path unless Dir.exist?(integration_path)

        integration_path
      end

      def pad(depth = 0)
        " " * depth
      end

    end
  end
end
