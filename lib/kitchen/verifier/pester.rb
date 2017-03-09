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

require 'pathname'
require 'kitchen/verifier/base'
require 'kitchen/verifier/pester_version'

module Kitchen

  module Verifier

    class Pester < Kitchen::Verifier::Base

      kitchen_verifier_api_version 1

      plugin_version Kitchen::Verifier::PESTER_VERSION

      default_config :restart_winrm, false
      default_config :test_folder
      default_config :use_local_pester_module, false

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
      def prepare_command
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

      #private
      def run_command_script
        <<-CMD
          $TestPath = "#{config[:root_path]}";
          import-module Pester -force;
          $result = invoke-pester -path $testpath -passthru ;
          $result |
            export-clixml (join-path $testpath 'result.xml');
          $host.setshouldexit($result.failedcount)
        CMD
      end

      def really_wrap_shell_code(code)
        wrap_shell_code(Util.outdent!(use_local_powershell_modules(code)))
      end

      def use_local_powershell_modules(script)
        <<-EOH
          set-executionpolicy unrestricted -force;
          $global:ProgressPreference = 'SilentlyContinue'
          #{"$VerbosePreference = 'Continue'" if instance.logger.logdev.level == 0}
          $env:psmodulepath += ";$(join-path (resolve-path $env:temp).path 'verifier/modules')";
          # $env:psmodulepath -split ';' | % {write-output "PSModulePath contains:"} {write-output "`t$_"}
          #{script}
        EOH
      end

      def random_string
        (0...8).map { (65 + rand(26)).chr }.join
      end

      def install_command_script
      <<-EOH
        function directory($path){
          if (test-path $path) {(resolve-path $path).providerpath}
          else {(resolve-path (mkdir $path)).providerpath}
        }
        $VerifierModulePath = directory $env:temp/verifier/modules
        $VerifierTestsPath = directory $env:temp/verifier/pester

	$env:psmodulepath += ";$VerifierModulePath"
        function test-module($module){
          (get-module $module -list) -ne $null
        }
        if (-not (test-module pester)) {
          if (test-module PowerShellGet){
            import-module PowerShellGet -force
            import-module PackageManagement -force
            get-packageprovider -name NuGet -force | out-null
            install-module Pester -force
          }
          else {
            if (-not (test-module PsGet)){
            $wc = New-Object -TypeName Net.WebClient

            if($env:http_Proxy){
              if($env:no_proxy){
                Write-Output "Creating WebProxy with 'http_proxy' and 'no_proxy' environment variables.	
                  $webproxy = New-Object System.Net.WebProxy($env:http_Proxy,$true,$env:no_proxy)
                  }else{
                Write-Output "Creating WebProxy with 'http_proxy' environment variable.
                $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList ($env:http_Proxy)
              }
              
              $wc.proxy = $webproxy    
            }
              
            Invoke-Expression -Command $wc.DownloadString('http://bit.ly/GetPsGet')
            }
            try {
              import-module psget -force -erroraction stop
              Install-Module Pester
            }
            catch {
              Write-Output "Installing from Github"
              $zipfile = join-path(resolve-path "$env:temp/verifier") "pester.zip"
              if (-not (test-path $zipfile)){
                $source = 'https://github.com/pester/Pester/archive/3.3.14.zip'
                $wc = New-Object -TypeName Net.WebClient

                if($env:http_Proxy){
                  if($env:no_proxy){
                    Write-Output "Creating WebProxy with 'http_proxy' and 'no_proxy' environment variables."	
                    $webproxy = New-Object System.Net.WebProxy($env:http_Proxy,$true,$env:no_proxy)
                  }else{
                    Write-Output "Creating WebProxy with 'http_proxy' environment variable."
                    $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList ($env:http_Proxy)
                  }
	        
                $wc.proxy = $webproxy    
                }

                [byte[]]$bytes = $wc.DownloadData($source)
                [IO.File]::WriteAllBytes($zipfile, $bytes)
                $bytes = $null
                [gc]::collect()
                write-output "Downloaded Pester.zip"
              }
              write-output "Creating Shell.Application COM object"
              $shellcom = new-object -com shell.application
              Write-Output "Creating COM object for zip file."
              $zipcomobject = $shellcom.namespace($zipfile)
              Write-Output "Creating COM object for module destination."
              $destination = $shellcom.namespace($VerifierModulePath)
              Write-Output "Unpacking zip file."
              $destination.CopyHere($zipcomobject.Items(), 0x610)
              rename-item (join-path $VerifierModulePath "Pester-3.3.14") -newname 'Pester' -force
            }
          }
        }
        if (-not (test-module Pester)) {
          throw "Unable to install Pester.  Please include Pester in your base image or install during your converge."
        }
      EOH
      end

      def restart_winrm_service

        cmd = 'schtasks /Create /TN restart_winrm /TR ' \
              '"powershell -command restart-service winrm" ' \
              '/SC ONCE /ST 00:00 '
        wrap_shell_code(Util.outdent!(<<-CMD
          #{cmd}
          schtasks /RUN /TN restart_winrm
        CMD
        ))
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
        File.join(sandbox_path, path.sub("#{suite_test_folder}/", ""))
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
        %w[PesterUtil].each do |module_name|
          prepare_powershell_module module_name
        end

      end

      def test_folder
        return config[:test_base_path] if config[:test_folder].nil?
        absolute_test_folder
      end

      def absolute_test_folder
        path = (Pathname.new config[:test_folder]).realpath
        integration_path = File.join(path, 'integration')
        return path unless Dir.exist?(integration_path)
        integration_path
      end

    end
  end
end
