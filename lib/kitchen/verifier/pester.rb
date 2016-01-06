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
        prepare_pester_tests
      end

      # Generates a command string which will install and configure the
      # verifier software on an instance. If no work is required, then `nil`
      # will be returned.
      #
      # @return [String] a command string
      def install_command
        return if local_suite_files.empty?

        cmd = <<-CMD
          set-executionpolicy unrestricted -force
          if (-not (get-module -list pester)) {
            if (get-module -list PowerShellGet){
              import-module PowerShellGet -force
              install-module Pester -force
            }
            else {
              if (-not (get-module -list PsGet)){
                iex (new-object Net.WebClient).DownloadString('http://bit.ly/GetPsGet')
              }
              import-module psget -force
              Install-Module Pester
            }
          }
        CMD
        wrap_shell_code(Util.outdent!(cmd))
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
        wrap_shell_code(Util.outdent!(<<-CMD
          $global:ProgressPreference = 'SilentlyContinue'
          $TestPath = "#{File.join(config[:root_path], 'suites')}"
          import-module Pester -force; invoke-pester -path $testpath -enableexit
        CMD
        ))
      end

      #private

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

      def local_suite_files
        base = File.join(test_folder, config[:suite_name])
        top_level_glob = File.join(base, "*")
        folder_glob = File.join(base, "*/**/*")
        top = Dir.glob(top_level_glob)
        nested = Dir.glob(folder_glob)
        (top << nested).flatten!.reject do |f|
          File.directory?(f)
        end
      end

      # Copies all test suite files into the suites directory in the sandbox.
      #
      # @api private
      def prepare_pester_tests
        base = File.join(test_folder, config[:suite_name])
        info("Preparing to copy files from #{base} to the SUT.")

        local_suite_files.each do |src|
          dest = File.join(sandbox_suites_dir, src.sub("#{base}/", ""))
          debug("Copying #{src} to #{dest}")
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest, preserve: true)
        end
      end

      # @return [String] path to suites directory under sandbox path
      # @api private
      def sandbox_suites_dir
        File.join(sandbox_path, "suites")
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
