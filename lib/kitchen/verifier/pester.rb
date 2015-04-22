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

require "kitchen/verifier/base"
require 'kitchen/verifier/pester_version'

module Kitchen

  module Verifier

    class Pester < Kitchen::Verifier::Base

      kitchen_verifier_api_version 1

      plugin_version Kitchen::Verifier::PESTER_VERSION

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
          if (-not (get-module -list pester)) {
            if (-not (get-module PsGet)){
              iex (new-object Net.WebClient).DownloadString('http://bit.ly/GetPsGet')
            }
            Import-Module PsGet
            Install-Module Pester
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

        wrap_shell_code(Util.outdent!(<<-CMD))
          cd "#{File.join(config[:root_path],'suites/pester/' )}"
          invoke-pester
        CMD
      end

      #private

      # Returns an Array of test suite filenames for the related suite currently
      # residing on the local workstation. Any special provisioner-specific
      # directories (such as a Chef roles/ directory) are excluded.
      #
      # @return [Array<String>] array of suite files
      # @api private

      def local_suite_files
        base = File.join(config[:test_base_path], config[:suite_name])
        glob = File.join(base, "*/**/*")
        Dir.glob(glob).reject do |f|
          File.directory?(f)
        end
      end

      # Copies all test suite files into the suites directory in the sandbox.
      #
      # @api private
      def prepare_pester_tests
        base = File.join(config[:test_base_path], config[:suite_name])

        local_suite_files.each do |src|
          dest = File.join(sandbox_suites_dir, src.sub("#{base}/", ""))
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(src, dest, :preserve => true)
        end
      end

      # @return [String] path to suites directory under sandbox path
      # @api private
      def sandbox_suites_dir
        File.join(sandbox_path, "suites")
      end

    end
  end
end