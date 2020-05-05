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

require "pathname"
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
      default_config :use_local_pester_module, false
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

      # Generates a command string which will install and configure the
      # verifier software on an instance. If no work is required, then `nil`
      # will be returned.
      #
      # @return [String] a command string
      def install_command
        return if local_suite_files.empty?
        return if config[:use_local_pester_module]

        really_wrap_shell_code(install_command_script)
      end

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
      def prepare_command; end

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
        def call (state)
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

          $TestPath = "#{config[:root_path]}"
          $OutputFilePath = Join-Path $TestPath -ChildPath 'PesterTestResults.xml'

          $options = New-PesterOption -TestSuiteName "Pester - #{instance.to_str}"

          $result = Invoke-Pester -Script $TestPath -OutputFile $OutputFilePath -OutputFormat NUnitXml -PesterOption $options -PassThru
          $result | Export-CliXml -Path (Join-Path -Path $TestPath -ChildPath 'result.xml')

          $LASTEXITCODE = $result.FailedCount
          $host.SetShouldExit($LASTEXITCODE)

          exit $LASTEXITCODE
        CMD
      end

      def really_wrap_shell_code(code)
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
          $env:PSModulePath = "$(Join-Path (Get-Item -Path $env:TEMP).FullName -ChildPath 'verifier/modules');$env:PSModulePath"

          #{script}
        EOH
      end

      def install_command_script
        <<-EOH
          [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

          function Confirm-Directory {
              [CmdletBinding()]
              param($Path)

              $Item = if (Test-Path $Path) {
                  Get-Item -Path $Path
              }
              else {
                  New-Item -Path $Path -ItemType Directory
              }

              $Item.FullName
          }

          function Test-Module {
              [CmdletBinding()]
              param($Name)

              @(Get-Module -Name $Name -ListAvailable -ErrorAction SilentlyContinue).Count -gt 0
          }

          $VerifierModulePath = Confirm-Directory -Path $env:TEMP/verifier/modules
          $VerifierTestsPath = Confirm-Directory -Path $env:TEMP/verifier/pester

          $env:PSModulePath = "$VerifierModulePath;$PSModulePath"

          if (-not (Test-Module -Name Pester)) {
              if (Test-Module -Name PowerShellGet) {
                  Import-Module PowerShellGet -Force
                  Import-Module PackageManagement -Force

                  Get-PackageProvider -Name NuGet -Force > $null

                  Install-Module Pester -Force
              }
              else {
                  if (-not (Test-Module -Name PsGet)){
                      $webClient = New-Object -TypeName System.Net.WebClient

                      if ($env:HTTP_PROXY){
                          if ($env:NO_PROXY){
                              Write-Host "Creating WebProxy with 'HTTP_PROXY' and 'NO_PROXY' environment variables.
                              $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList $env:HTTP_PROXY, $true, $env:NO_PROXY
                          }
                          else {
                              Write-Host "Creating WebProxy with 'HTTP_PROXY' environment variable.
                              $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList $env:HTTP_PROXY
                          }

                          $webClient.Proxy = $webproxy
                      }

                      Invoke-Expression -Command $webClient.DownloadString('http://bit.ly/GetPsGet')
                  }

                  try {
                      # If the module isn't already loaded, ensure we can import it.
                      if (-not (Get-Module -Name PsGet -ErrorAction SilentlyContinue)) {
                          Import-Module -Name PsGet -Force -ErrorAction Stop
                      }

                      Install-Module -Name Pester -Force
                  }
                  catch {
                      Write-Host "Installing from Github"

                      $downloadFolder = if (Test-Path "$env:TEMP/PesterDownload") {
                          "$env:TEMP/PesterDownload"
                      }
                      else {
                          New-Item -ItemType Directory -Path "$env:TEMP/PesterDownload"
                      }

                      $zipFile = Join-Path (Get-Item -Path $downloadFolder).FullName -ChildPath "pester.zip"

                      if (-not (Test-Path $zipfile)) {
                          $source = 'https://github.com/pester/Pester/archive/4.10.1.zip'
                          $webClient = New-Object -TypeName Net.WebClient

                          if ($env:HTTP_PROXY) {
                              if ($env:NO_PROXY) {
                                  Write-Host "Creating WebProxy with 'HTTP_PROXY' and 'NO_PROXY' environment variables."
                                  $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList $env:HTTP_PROXY, $true, $env:NO_PROXY
                              }
                              else {
                                  Write-Host "Creating WebProxy with 'HTTP_PROXY' environment variable."
                                  $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList $env:HTTP_PROXY
                              }

                              $webClient.Proxy = $webproxy
                          }

                          [IO.File]::WriteAllBytes($zipfile, $webClient.DownloadData($source))

                          [GC]::Collect()
                          Write-Host "Downloaded Pester.zip"
                      }

                      Write-Host "Creating Shell.Application COM object"
                      $shellcom = New-Object -ComObject Shell.Application

                      Write-Host "Creating COM object for zip file."
                      $zipcomobject = $shellcom.Namespace($zipfile)

                      Write-Host "Creating COM object for module destination."
                      $destination = $shellcom.Namespace($VerifierModulePath)

                      Write-Host "Unpacking zip file."
                      $destination.CopyHere($zipcomobject.Items(), 0x610)

                      Rename-Item -Path (Join-Path $VerifierModulePath -ChildPath "Pester-4.10.1") -NewName 'Pester' -Force
                  }
              }
          }

          if (-not (Test-Module Pester)) {
              throw "Unable to install Pester.  Please include Pester in your base image or install during your converge."
          }
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

            Array(remotes).each do |file|
              safe_name = instance.name.gsub(/[^0-9A-Z-]/i, "_")
              local_path = File.join(local, safe_name, file)
              remote_path = File.join(config[:root_path], file)

              conn.download(remote_path, local_path)
            end
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

      def suite_level_glob
        Dir.glob(File.join(suite_test_folder, "*"))
      end

      def suite_verifier_level_glob
        Dir.glob(File.join(suite_test_folder, "*/**/*"))
      end

      def local_suite_files
        suite = suite_level_glob
        suite_verifier = suite_verifier_level_glob
        (suite << suite_verifier).flatten!.reject do |f|
          File.directory?(f)
        end
      end

      def sandboxify_path(path)
        File.join(sandbox_path, path.sub(%r{#{suite_test_folder}/}i, ""))
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

    end
  end
end
