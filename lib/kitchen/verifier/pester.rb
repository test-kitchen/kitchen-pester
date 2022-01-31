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

require "fileutils" unless defined?(FileUtils)
require "pathname" unless defined?(Pathname)
require "kitchen/util"
require "kitchen/verifier/base"
require "kitchen/version"
require "base64" unless defined?(Base64)
require_relative "pester_version"

module Kitchen

  module Verifier

    class Pester < Kitchen::Verifier::Base

      kitchen_verifier_api_version 1

      plugin_version Kitchen::Verifier::PESTER_VERSION

      default_config :restart_winrm, false
      default_config :test_folder, "tests"
      default_config :remove_builtin_powershellget, true
      default_config :remove_builtin_pester, true
      default_config :skip_pester_install, false
      default_config :bootstrap, {
        repository_url: "https://www.powershellgallery.com/api/v2",
        modules: [],
      }
      default_config :register_repository, []
      default_config :pester_install, {
        SkipPublisherCheck: true,
        Force: true,
        ErrorAction: "Stop",
      }
      default_config :pester_configuration, {
        run: {
          path: ".",
          PassThru: true,
        },
        TestResult: {
          Enabled: true,
          OutputPath: "PesterTestResults.xml",
          TestSuiteName: "",
        },
        Output: {
          Verbosity: "Detailed",
        },
      }
      default_config :install_modules, []
      default_config :downloads, { "./PesterTestResults.xml" => "./testresults/" }
      default_config :copy_folders, []
      default_config :sudo, false
      default_config :shell, nil
      default_config :environment, {}

      # Creates a new Verifier object using the provided configuration data
      # which will be merged with any default configuration.
      #
      # @param config [Hash] provided verifier configuration
      def initialize(config = {})
        init_config(config)
        raise ClientError.new "Environment Variables must be specified as a hash, not a #{config[:environment].class}" unless config[:environment].is_a?(Hash)
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
        prepare_supporting_psmodules
        prepare_copy_folders
        prepare_pester_tests
        prepare_helpers

        debug("\n\n")
        debug("Sandbox content:\n")
        list_files(sandbox_path).each do |f|
          debug("    #{f}")
        end
      end

      # Generates a command string which will install and configure the
      # verifier software on an instance. If no work is required, then `nil`
      # will be returned.
      # PowerShellGet & Pester Bootstrap are done in prepare_command (after sandbox is transferred)
      # so that we can use the PesterUtil.psm1
      #
      # @return [String] a command string
      def install_command
        # the sandbox has not yet been copied to the SUT.
        install_command_string = <<-PS1
          Write-Verbose 'Running Install Command...'
          $modulesToRemove = @(
              if ($#{config[:remove_builtin_powershellget]}) {
                  Get-module -ListAvailable -FullyQualifiedName @{ModuleName = 'PackageManagement'; RequiredVersion = '1.0.0.1'}
                  Get-module -ListAvailable -FullyQualifiedName @{ModuleName = 'PowerShellGet'; RequiredVersion = '1.0.0.1'}
              }

              if ($#{config[:remove_builtin_pester]}) {
                  Get-module -ListAvailable -FullyQualifiedName @{ModuleName = 'Pester'; RequiredVersion = '3.4.0'}
              }
          )

          if ($modulesToRemove.ModuleBase.Count -eq 0) {
            # for PS7 on linux
            return
          }

          $modulesToRemove.ModuleBase | Foreach-Object {
              $ModuleBaseLeaf = Split-Path -Path $_ -Leaf
              if ($ModuleBaseLeaf -as [System.version]) {
                Remove-Item -force -Recurse (Split-Path -Parent -Path $_) -ErrorAction SilentlyContinue
              }
              else {
                Remove-Item -force -Recurse $_ -ErrorAction SilentlyContinue
              }
          }
        PS1
        really_wrap_shell_code(Util.outdent!(install_command_string))
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
        info("Preparing the SUT and Pester dependencies...")
        resolve_downloads_paths!
        really_wrap_shell_code(install_command_script)
      end

      # Generates a command string which will invoke the main verifier
      # command on the prepared instance. If no work is required, then `nil`
      # will be returned.
      #
      # @return [String] a command string
      def run_command
        really_wrap_shell_code(invoke_pester_scriptblock)
      end

      # Resolves the remote Downloads path from the verifier root path,
      # unless they're absolute path (starts with / or C:\)
      # This updates the config[:downloads], nothing (nil) is returned.
      #
      # @return [nil] updates config downloads
      def resolve_downloads_paths!
        info("Resolving Downloads path from config.")
        config[:downloads] = config[:downloads]
          .map do |source, destination|
            source = source.to_s
            info("  resolving remote source's absolute path.")
            unless source.match?('^/|^[a-zA-Z]:[\\/]') # is Absolute?
              info("  '#{source}' is a relative path, resolving to: #{File.join(config[:root_path], source)}")
              source = File.join(config[:root_path], source.to_s).to_s
            end

            if destination.match?('\\$|/$') # is Folder (ends with / or \)
              destination = File.join(destination, File.basename(source)).to_s
            end
            info("  Destination: #{destination}")
            if !File.directory?(File.dirname(destination))
              FileUtils.mkdir_p(File.dirname(destination))
            else
              info("  Directory #{File.dirname(destination)} seem to exist.")
            end

            [ source, destination ]
          end
        nil # make sure we do not return anything
      end

      # Download functionality was added to the base verifier behavior after
      # version 2.3.4
      if Gem::Version.new(Kitchen::VERSION) <= Gem::Version.new("2.3.4")
        def call(state)
          super
        ensure
          info("Ensure download test files.")
          download_test_files(state) unless config[:downloads].nil?
          info("Download complete.")
        end
      else
        def call(state)
          super
        rescue
          # If the verifier reports failure, we need to download the files ourselves.
          # Test Kitchen's base verifier doesn't have the download in an `ensure` block.
          info("Rescue to download test files.")
          download_test_files(state) unless config[:downloads].nil?
          # Rethrow original exception, we still want to register the failure.
          raise
        end
      end

      # private
      def invoke_pester_scriptblock
        <<-PS1
          $PesterModule = Import-Module -Name Pester -Force -ErrorAction Stop -PassThru

          $TestPath = Join-Path "#{config[:root_path]}" -ChildPath "suites"
          $OutputFilePath = Join-Path "#{config[:root_path]}" -ChildPath 'PesterTestResults.xml'

          #{ps_environment(config[:environment])}
          if ($PesterModule.Version.Major -le 4)
          {
            Write-Host -Object "Invoke Pester with v$($PesterModule.Version) Options"
            $options = New-PesterOption -TestSuiteName "Pester - #{instance.to_str}"
            $defaultPesterParameters = @{
                Script        = $TestPath
                OutputFile    = $OutputFilePath
                OutputFormat  = 'NUnitXml'
                PassThru      = $true
                PesterOption  = $options
            }

            $pesterCmd = Get-Command -Name 'Invoke-Pester'
            $pesterConfig = #{ps_hash(config[:pester_configuration])}
            $invokePesterParams = @{}

            foreach ($paramName in $pesterCmd.Parameters.Keys)
            {
                $paramValue = $pesterConfig.($paramName)

                if ($paramValue) {
                    Write-Host -Object "Using $paramName from Yaml config."
                    $invokePesterParams[$paramName] = $paramValue
                }
                elseif ($defaultPesterParameters.ContainsKey($paramName))
                {
                    Write-Host -Object "Using $paramName from Defaults: $($defaultPesterParameters[$paramName])."
                    $invokePesterParams[$paramName] = $defaultPesterParameters[$paramName]
                }
            }

            $result = Invoke-Pester @invokePesterParams
          }
          else
          {
            Write-Host -Object "Invoke Pester with v$($PesterModule.Version) Configuration."
            $pesterConfigHash = #{ps_hash(config[:pester_configuration])}

            if (-not $pesterConfigHash.ContainsKey('run')) {
                $pesterConfigHash['run'] = @{}
            }

            if (-not $pesterConfigHash.ContainsKey('TestResult')) {
                $pesterConfigHash['TestResult'] = @{}
            }

            if (-not $pesterConfigHash.run.path) {
                $pesterConfigHash['run']['path'] = $TestPath
            }

            if (-not $pesterConfigHash.TestResult.TestSuiteName) {
                $pesterConfigHash['TestResult']['TestSuiteName'] = 'Pester - #{instance.to_str}'
            }

            if (-not $pesterConfigHash.TestResult.OutputPath) {
                $pesterConfigHash['TestResult']['OutputPath'] = $OutputFilePath
            }

            $PesterConfig = New-PesterConfiguration -Hashtable $pesterConfigHash
            $result = Invoke-Pester -Configuration $PesterConfig
          }

          $resultXmlPath = (Join-Path -Path $TestPath -ChildPath 'result.xml')
          if (Test-Path -Path $resultXmlPath) {
            $result | Export-CliXml -Path
          }

          $LASTEXITCODE = $result.FailedCount
          $host.SetShouldExit($LASTEXITCODE)

          exit $LASTEXITCODE
        PS1
      end

      def get_powershell_modules_from_nugetapi
        # don't return anything is the modules subkey or bootstrap is null
        return if config.dig(:bootstrap, :modules).nil?

        bootstrap = config[:bootstrap]
        # if the repository url is set, use that as parameter to Install-ModuleFromNuget. Default is the PSGallery url
        gallery_url_param = bootstrap[:repository_url] ? "-GalleryUrl '#{bootstrap[:repository_url]}'" : ""

        info("Bootstrapping environment without PowerShellGet Provider...")
        Array(bootstrap[:modules]).map do |powershell_module|
          if powershell_module.is_a? Hash
            <<-PS1
              ${#{powershell_module[:Name]}} = #{ps_hash(powershell_module)}

              Install-ModuleFromNuget -Module ${#{powershell_module[:Name]}} #{gallery_url_param}
            PS1
          else
            <<-PS1
              Install-ModuleFromNuget -Module @{Name = '#{powershell_module}'} #{gallery_url_param}
            PS1
          end
        end
      end

      # Returns the string command to set a PS Repository
      # for each PSRepo configured.
      #
      # @return [Array<String>] array of suite files
      # @api private
      def register_psrepository_scriptblock
        return if config[:register_repository].nil?

        info("Registering a new PowerShellGet Repository")
        Array(config[:register_repository]).map do |psrepo|
          # Using Set-PSRepo from ../../*/*/*/PesterUtil.psm1
          debug("Command to set PSRepo #{psrepo[:Name]}.")
          <<-PS1
            Write-Host 'Registering psrepo #{psrepo[:Name]}...'
            ${#{psrepo[:Name]}} = #{ps_hash(psrepo)}
            Set-PSRepo -Repository ${#{psrepo[:Name]}}
          PS1
        end
      end

      # Returns the string command set the PSGallery as trusted, and
      # Install Pester from gallery based on the params from Pester_install_params config
      #
      # @return <String> command to install Pester Module
      # @api private
      def install_pester
        return if config[:skip_pester_install]

        pester_install_params = config[:pester_install] || {}
        <<-PS1
          if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne 'Trusted') {
              Write-Host -Object "Trusting the PSGallery to install Pester without -Force"
              Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
          }

          Write-Host "Installing Pester..."
          $installPesterParams = #{ps_hash(pester_install_params)}
          $installPesterParams['Name'] = 'Pester'
          Install-module @installPesterParams
          Write-Host 'Pester Installed.'
        PS1
      end

      # returns a piece of PS scriptblock for each Module to install
      # from gallery that has been sepcified in install_modules config.
      #
      # @return [Array<String>] array of PS commands.
      # @api private
      def install_modules_from_gallery
        return if config[:install_modules].nil?

        Array(config[:install_modules]).map do |powershell_module|
          if powershell_module.is_a? Hash
            # Sanitize variable name so that $powershell-yaml becomes $powershell_yaml
            module_name = powershell_module[:Name].gsub(/[\W]/, "_")
            # so we can splat that variable to install module
            <<-PS1
              $#{module_name} = #{ps_hash(powershell_module)}
              Write-Host -NoNewline 'Installing #{module_name}'
              Install-Module @#{module_name}
              Write-host '... done.'
            PS1
          else
            <<-PS1
              Write-host -NoNewline 'Installing #{powershell_module} ...'
              Install-Module -Name '#{powershell_module}'
              Write-host '... done.'
            PS1
          end
        end
      end

      def really_wrap_shell_code(code)
        windows_os? ? really_wrap_windows_shell_code(code) : really_wrap_posix_shell_code(code)
      end

      # Get the defined shell or fall back to pwsh, unless we're on windows where we use powershell
      # call via sudo if sudo is true.
      # This allows to use pwsh-preview instead of pwsh, or a full path to a specific binary.
      def shell_cmd
        if !config[:shell].nil?
          config[:sudo] ? "sudo #{config[:shell]}" : "#{config[:shell]}"
        elsif windows_os?
          "powershell"
        else
          config[:sudo] ? "sudo pwsh" : "pwsh"
        end
      end

      def really_wrap_windows_shell_code(code)
        my_command = <<-PWSH
          echo "Running as '$(whoami)'..."
          New-Item -ItemType Directory -Path '#{config[:root_path]}/modules' -Force -ErrorAction SilentlyContinue
          Set-Location -Path "#{config[:root_path]}"
          # Send the pwsh here string to the file kitchen_cmd.ps1
          @'
          try {
              if (@('Bypass', 'Unrestricted') -notcontains (Get-ExecutionPolicy)) {
                  Set-ExecutionPolicy Unrestricted -Force -Scope Process
              }
          }
          catch {
              $_ | Out-String | Write-Warning
          }
          #{Util.outdent!(use_local_powershell_modules(code))}
          '@ | Set-Content -Path kitchen_cmd.ps1 -Encoding utf8 -Force -ErrorAction 'Stop'
          # create the modules folder, making sure it's done as current user (not root)
          #
          # Invoke the created kitchen_cmd.ps1 file using pwsh
          #{shell_cmd} ./kitchen_cmd.ps1
        PWSH
        wrap_shell_code(Util.outdent!(my_command))
      end

      # Writing the command to a ps1 file, adding the pwsh shebang
      # invoke the file
      def really_wrap_posix_shell_code(code)
        my_command = <<-BASH
          echo "Running as '$(whoami)'"
          # create the modules folder, making sure it's done as current user (not root)
          mkdir -p #{config[:root_path]}/modules
          cd #{config[:root_path]}
          # Send the bash heredoc 'EOF' to the file kitchen_cmd.ps1 using the tool cat
          cat << 'EOF' > kitchen_cmd.ps1
          #!/usr/bin/env pwsh
          #{Util.outdent!(use_local_powershell_modules(code))}
          EOF
          chmod +x kitchen_cmd.ps1
          # Invoke the created kitchen_cmd.ps1 file using pwsh
          #{shell_cmd} ./kitchen_cmd.ps1
        BASH

        debug(Util.outdent!(my_command))
        Util.outdent!(my_command)
      end

      def use_local_powershell_modules(script)
        <<-PS1
          Write-Host -Object ("{0} - PowerShell {1}" -f $PSVersionTable.OS,$PSVersionTable.PSVersion)
          $global:ProgressPreference = 'SilentlyContinue'
          $PSModPathToPrepend = Join-Path "#{config[:root_path]}" -ChildPath 'modules'
          Write-Verbose "Adding '$PSModPathToPrepend' to `$Env:PSModulePath."
          if (!$isLinux -and -not (Test-Path -Path $PSModPathToPrepend)) {
            # if you create this folder now in Linux, it may run as root (via sudo).
            $null = New-Item -Path $PSModPathToPrepend -Force -ItemType Directory
          }

          if ($Env:PSModulePath.Split([io.path]::PathSeparator) -notcontains $PSModPathToPrepend) {
            $env:PSModulePath   = @($PSModPathToPrepend, $env:PSModulePath) -Join [io.path]::PathSeparator
          }

          #{script}
        PS1
      end

      def install_command_script
        <<-PS1
          $PSModPathToPrepend = "#{config[:root_path]}"

          Import-Module -ErrorAction Stop PesterUtil

          #{get_powershell_modules_from_nugetapi.join("\n") unless config.dig(:bootstrap, :modules).nil?}

          #{register_psrepository_scriptblock.join("\n") unless config[:register_repository].nil?}

          #{install_pester}

          #{install_modules_from_gallery.join("\n") unless config[:install_modules].nil?}
        PS1
      end

      def restart_winrm_service
        return unless verifier.windows_os?

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
        if config[:downloads].nil?
          info("Skipped downloading test result file from #{instance.to_str}; 'downloads' hash is empty.")
          return
        end

        info("Downloading test result files from #{instance.to_str}")
        instance.transport.connection(state) do |conn|
          config[:downloads].each do |remotes, local|
            debug("downloading #{Array(remotes).join(", ")} to #{local}")
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

      # Returns the current file's parent folder's full path.
      #
      # @return [string]
      # @api private
      def script_root
        @script_root ||= File.dirname(__FILE__)
      end

      # Returns the absolute path of the Supporting PS module to
      # be copied to the SUT via the Sandbox.
      #
      # @return [string]
      # @api private
      def support_psmodule_folder
        @support_psmodule_folder ||= Pathname.new(File.join(script_root, "../../support/modules/PesterUtil")).cleanpath
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

      # Creates a PowerShell hashtable from a ruby map.
      # The only types supported for now are hash, array, string and Boolean.
      #
      # @api private
      def ps_hash(obj, depth = 0)
        if [true, false].include? obj
          %{$#{obj}} # Return $true or $false when value is a bool
        elsif obj.is_a?(Hash)
          obj.map do |k, v|
            # Format "Key = Value" enabling recursion
            %{#{pad(depth + 2)}#{ps_hash(k)} = #{ps_hash(v, depth + 2)}}
          end
            .join("\n") # append \n to the key/value definitions
            .insert(0, "@{\n") # prepend @{\n
            .insert(-1, "\n#{pad(depth)}}\n") # append \n}\n

        elsif obj.is_a?(Array)
          array_string = obj.map { |v| ps_hash(v, depth + 4) }.join(",")
          "#{pad(depth)}@(\n#{array_string}\n)"
        else
          # When the object is not a string nor a hash or array, it will be quoted as a string.
          # In most cases, PS is smart enough to convert back to the type it needs.
          "'" + obj.to_s + "'"
        end
      end

      # Creates environment variable assignments from a ruby map.
      #
      # @api private
      def ps_environment(obj)
        commands = obj.map do |k, v|
          "$env:#{k} = '#{v}'"
        end

        commands.join("\n")
      end

      # returns the path of the modules subfolder
      # in the sandbox, where PS Modules and folders will be copied to.
      #
      # @api private
      def sandbox_module_path
        File.join(sandbox_path, "modules")
      end

      # copy files into the 'modules' folder of the sandbox,
      # so that copied folders can be discovered with the updated $Env:PSModulePath.
      #
      # @api private
      def prepare_copy_folders
        return if config[:copy_folders].nil?

        info("Preparing to copy specified folders to #{sandbox_module_path}.")
        kitchen_root_path = config[:kitchen_root]
        config[:copy_folders].each do |folder|
          debug("copying #{folder}")
          folder_to_copy = File.join(kitchen_root_path, folder)
          copy_if_src_exists(folder_to_copy, sandbox_module_path)
        end
      end

      # returns an array of string
      # Creates a flat list of files contained in a folder.
      # This is useful when trying to debug what has been copied to
      # the sandbox.
      #
      # @return [Array<String>] array of files in a folder
      # @api private
      def list_files(path)
        base_directory_content = Dir.glob(File.join(path, "*"))
        nested_directory_content = Dir.glob(File.join(path, "*/**/*"))
        [base_directory_content, nested_directory_content].flatten
      end

      # Copies all test suite files into the suites directory in the sandbox.
      #
      # @api private
      def prepare_pester_tests
        info("Preparing to copy files from  '#{suite_test_folder}' to the SUT.")
        sandboxed_suites_path = File.join(sandbox_path, "suites")
        copy_if_src_exists(suite_test_folder, sandboxed_suites_path)
      end

      def prepare_supporting_psmodules
        info("Preparing to copy files from '#{support_psmodule_folder}' to the SUT.")
        sandbox_module_path = File.join(sandbox_path, "modules")
        copy_if_src_exists(support_psmodule_folder, sandbox_module_path)
      end

      # Copies a folder recursively preserving its layers,
      # mostly used to copy to the sandbox.
      #
      # @api private
      def copy_if_src_exists(src_to_validate, destination)
        unless Dir.exist?(src_to_validate)
          info("The path #{src_to_validate} was not found. Not copying to #{destination}.")
          return
        end

        info("Moving #{src_to_validate} to #{destination}")
        unless Dir.exist?(destination)
          FileUtils.mkdir_p(destination)
          debug("Folder '#{destination}' created.")
        end
        FileUtils.mkdir_p(File.join(destination, "__bugfix"))
        FileUtils.cp_r(src_to_validate, destination, preserve: true)
      end

      # returns the absolute path of the folders containing the
      # test suites, use default if not set.
      #
      # @api private
      def test_folder
        config[:test_folder].nil? ? config[:test_base_path] : absolute_test_folder
      end

      # returns the absolute path of the relative folders containing the
      # test suites, use default i not set.
      #
      # @api private
      def absolute_test_folder
        path = (Pathname.new config[:test_folder]).realpath
        integration_path = File.join(path, "integration")
        Dir.exist?(integration_path) ? integration_path : path
      end

      # returns a string of space of the specified depth.
      # This is used to pad messages or when building PS hashtables.
      #
      # @api private
      def pad(depth = 0)
        " " * depth
      end
    end
  end
end
