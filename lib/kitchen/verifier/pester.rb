# frozen_string_literal: true

# Author:: Steven Murawski (<steven.murawski@gmail.com>)
#
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

require "fileutils" unless defined?(FileUtils)
require "pathname" unless defined?(Pathname)
require "kitchen/util"
require "kitchen/verifier/base"
require_relative "pester_version"

module Kitchen

  module Verifier

    # A Test Kitchen verifier that runs Pester tests on the system under test.
    #
    # The verifier does almost all of its work by generating PowerShell source
    # locally and handing it to the transport to execute remotely. Each command
    # hook -- {#install_command}, {#init_command}, {#prepare_command} and
    # {#run_command} -- returns a script string rather than performing the work
    # itself.
    #
    # Test files, helper files and any folders named in `copy_folders` are
    # staged into a sandbox by {#create_sandbox}, shipped to the instance, and
    # discovered there through `$Env:PSModulePath`.
    #
    # @example configuring the verifier in kitchen.yml
    #
    #   verifier:
    #     name: pester
    #     test_folder: tests
    #     install_modules:
    #       - PSScriptAnalyzer
    #     downloads:
    #       ./PesterTestResults.xml: ./testresults/
    #
    # @see https://pester.dev/ Pester
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
      #
      # @return [void]
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
            if destination.nil?
              raise UserError, "The verifier's 'downloads' entry for '#{source}' has no local " \
                               "destination. Every entry needs one, for example " \
                               "'#{source}: ./testresults/'."
            end

            destination = destination.to_s.gsub("%{instance_name}", instance.name)
            info("  resolving remote source's absolute path.")
            unless source.match?(%r{^/|^[a-zA-Z]:[\\/]}) # is Absolute?
              info("  '#{source}' is a relative path, resolving to: #{File.join(config[:root_path], source)}")
              source = File.join(config[:root_path], source.to_s).to_s
            end

            if destination.match?(%r{[\\/]$}) # is Folder (ends with / or \)
              # Append to the separator the user already supplied. File.join
              # would add a second one, of whichever flavour the workstation
              # happens to use.
              destination = "#{destination}#{remote_basename(source)}"
            end
            info("  Destination: #{destination}")
            if !File.directory?(File.dirname(destination))
              FileUtils.mkdir_p(File.dirname(destination))
            else
              info("  Directory #{File.dirname(destination)} seems to exist.")
            end

            [ source, destination ]
          end
          .to_h # Hash#map yields pairs; keep :downloads the hash it started as
        nil # make sure we do not return anything
      end

      # Runs the verifier on the instance, retrieving the test results even
      # when the run fails.
      #
      # @param state [Hash] mutable instance state
      # @raise [Kitchen::ActionFailed] if the verification failed
      # @return [void]
      def call(state)
        super
      rescue
        info("Rescue to download test files.")
        download_test_files(state) unless config[:downloads].nil?
        # Rethrow the original exception; the failure still has to register.
        raise
      end

      # Returns the PowerShell that imports Pester and invokes it.
      #
      # Two dialects are emitted behind a version check evaluated on the SUT:
      # Pester 4 and earlier take loose parameters, Pester 5 and later take a
      # `PesterConfiguration` object. The script exits with Pester's failed
      # test count so the transport registers the failure.
      #
      # @return [String] a PowerShell script
      # @api private
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
            $result | Export-CliXml -Path $resultXmlPath
          }

          $host.SetShouldExit($LASTEXITCODE)

          exit $LASTEXITCODE
        PS1
      end

      # Returns the commands that install the bootstrap modules straight from
      # a NuGet feed.
      #
      # This runs before PowerShellGet is available, so it uses
      # `Install-ModuleFromNuget` from PesterUtil.psm1 rather than
      # `Install-Module`. Each entry of `bootstrap.modules` may be a plain
      # module name or a hash of parameters.
      #
      # @return [Array<String>, nil] one PowerShell fragment per module, or nil
      #   when no bootstrap modules are configured
      # @api private
      def get_powershell_modules_from_nugetapi
        # don't return anything is the modules subkey or bootstrap is null
        return if config.dig(:bootstrap, :modules).nil?

        bootstrap = config[:bootstrap]
        # if the repository url is set, use that as parameter to Install-ModuleFromNuget. Default is the PSGallery url
        gallery_url_param = bootstrap[:repository_url] ? "-GalleryUrl '#{bootstrap[:repository_url]}'" : ""

        info("Bootstrapping environment without PowerShellGet Provider...")
        config_list("bootstrap.modules", bootstrap[:modules]).map do |powershell_module|
          if powershell_module.is_a? Hash
            module_name = module_name!("bootstrap.modules", powershell_module)
            <<-PS1
              ${#{module_name}} = #{ps_hash(powershell_module)}

              Install-ModuleFromNuget -Module ${#{module_name}} #{gallery_url_param}
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
        config_list("register_repository", config[:register_repository]).map do |psrepo|
          repo_name = module_name!("register_repository", psrepo)
          # Using Set-PSRepo from ../../*/*/*/PesterUtil.psm1
          debug("Command to set PSRepo #{repo_name}.")
          <<-PS1
            Write-Host 'Registering psrepo #{repo_name}...'
            ${#{repo_name}} = #{ps_hash(psrepo)}
            Set-PSRepo -Repository ${#{repo_name}}
          PS1
        end
      end

      # Returns the string command set the PSGallery as trusted, and
      # Install Pester from gallery based on the params from Pester_install_params config
      #
      # @return [String] command to install Pester Module
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
      # from gallery that has been specified in install_modules config.
      #
      # @return [Array<String>] array of PS commands.
      # @api private
      def install_modules_from_gallery
        return if config[:install_modules].nil?

        config_list("install_modules", config[:install_modules]).map do |powershell_module|
          if powershell_module.is_a? Hash
            # Sanitize variable name so that $powershell-yaml becomes $powershell_yaml
            module_name = module_name!("install_modules", powershell_module).gsub(/[\W]/, "_")
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

      # Note for anyone adding to the script builders below: Kitchen::Util.outdent!
      # mutates the string it is handed, and this file sets
      # `frozen_string_literal: true`. Interpolated literals are not frozen, so
      # every heredoc that reaches outdent! today is fine -- but a heredoc with
      # no `#{}` in it would be frozen and would raise FrozenError at runtime.
      # Use +dup+ on any such string before passing it along.

      # Wraps generated PowerShell in the platform's shell invocation.
      #
      # @param code [String] the PowerShell to run on the instance
      # @return [String] a shell command string
      # @api private
      def really_wrap_shell_code(code)
        windows_os? ? really_wrap_windows_shell_code(code) : really_wrap_posix_shell_code(code)
      end

      # Returns the shell binary used to run the generated script.
      #
      # An explicit `shell` config wins, which allows pwsh-preview or a full
      # path to a specific binary. Otherwise Windows uses powershell and every
      # other platform uses pwsh. `sudo` is honoured everywhere except the
      # Windows branch, where it is meaningless.
      #
      # @return [String] the shell command, prefixed with sudo when configured
      # @api private
      def shell_cmd
        if !config[:shell].nil?
          config[:sudo] ? "sudo #{config[:shell]}" : "#{config[:shell]}"
        elsif windows_os?
          "powershell"
        else
          config[:sudo] ? "sudo pwsh" : "pwsh"
        end
      end

      # Wraps PowerShell for a Windows instance.
      #
      # The payload is written to kitchen_cmd.ps1 and invoked, rather than
      # passed on the command line, so that quoting and length limits do not
      # apply to it.
      #
      # @param code [String] the PowerShell to run on the instance
      # @return [String] a shell command string
      # @api private
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

      # Wraps PowerShell for a non-Windows instance.
      #
      # Writes the payload to kitchen_cmd.ps1 through a quoted heredoc, so the
      # POSIX shell does not interpolate PowerShell variables, adds a pwsh
      # shebang and invokes it.
      #
      # @param code [String] the PowerShell to run on the instance
      # @return [String] a shell command string
      # @api private
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

      # Prefixes a script with the preamble that makes the sandbox's modules
      # folder importable.
      #
      # @param script [String] the PowerShell to run after the preamble
      # @return [String] the script with the PSModulePath preamble prepended
      # @api private
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

      # Returns the PowerShell that prepares the SUT once the sandbox has been
      # transferred.
      #
      # Runs after the transfer so that PesterUtil.psm1 is available to import.
      # Composes, in order: the NuGet bootstrap, any PSRepository registration,
      # the Pester install, and any gallery modules. Each section is omitted
      # when its config is nil.
      #
      # @return [String] a PowerShell script
      # @api private
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

      # Returns the command that schedules and runs a WinRM restart.
      #
      # The restart is driven through a scheduled task so that it survives the
      # WinRM session being torn down by the restart itself.
      #
      # @return [String, nil] a shell command string, or nil on a non-Windows
      #   instance
      # @api private
      def restart_winrm_service
        return unless windows_os?

        cmd = "schtasks /Create /TN restart_winrm /TR " \
              '"powershell -Command Restart-Service winrm" ' \
              "/SC ONCE /ST 00:00 "
        wrap_shell_code(Util.outdent!(<<-CMD
          #{cmd}
          schtasks /RUN /TN restart_winrm
        CMD
                                     ))
      end

      # Retrieves the configured result files from the instance.
      #
      # @param state [Hash] mutable instance state, used to open the transport
      #   connection
      # @return [void]
      # @api private
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
      # the sandbox, stripping the `helpers/` prefix from their paths.
      #
      # @return [void]
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

      # Renders a Ruby value as PowerShell source.
      #
      # Hashes become hashtables, arrays become arrays, booleans become $true
      # or $false, and everything else is quoted as a string -- PowerShell is
      # generally able to coerce it back to the type it needs.
      #
      # @param obj [Object] the value to render
      # @param depth [Integer] current nesting depth, used for indentation
      # @return [String] PowerShell source for the value
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
          ps_single_quote(obj)
        end
      end

      # Creates environment variable assignments from a ruby map.
      #
      # @param obj [Hash] variable names mapped to their values
      # @return [String] newline-separated `$env:NAME = 'value'` assignments
      # @api private
      def ps_environment(obj)
        commands = obj.map do |k, v|
          "$env:#{k} = #{ps_single_quote(v)}"
        end

        commands.join("\n")
      end

      # Renders a value as a single-quoted PowerShell string literal.
      #
      # PowerShell escapes a literal quote inside a single-quoted string by
      # doubling it. Without this an apostrophe anywhere in the config -- a
      # module name, an environment value, a password -- closes the string
      # early and corrupts the rest of the generated script.
      #
      # @param value [Object] any value; #to_s is used
      # @return [String] a quoted, escaped PowerShell string literal
      # @api private
      def ps_single_quote(value)
        "'#{value.to_s.gsub("'", "''")}'"
      end

      # Returns the path of the modules subfolder in the sandbox, where PS
      # modules and folders will be copied to.
      #
      # @return [String] absolute path to the sandbox's modules folder
      # @api private
      def sandbox_module_path
        File.join(sandbox_path, "modules")
      end

      # Copies the folders named in `copy_folders` into the sandbox's modules
      # folder, so they can be discovered through the updated
      # $Env:PSModulePath.
      #
      # @return [void]
      # @api private
      def prepare_copy_folders
        return if config[:copy_folders].nil?

        info("Preparing to copy specified folders to #{sandbox_module_path}.")
        kitchen_root_path = config[:kitchen_root]
        config_list("copy_folders", config[:copy_folders]).each do |folder|
          debug("copying #{folder}")
          folder_to_copy = File.join(kitchen_root_path, folder)
          copy_if_src_exists(folder_to_copy, sandbox_module_path)
        end
      end

      # Creates a flat list of the files contained in a folder.
      #
      # Useful when debugging what has actually been copied to the sandbox.
      #
      # @param path [String] the folder to list
      # @return [Array<String>] paths of the entries at the top level and
      #   nested beneath it
      # @api private
      def list_files(path)
        base_directory_content = Dir.glob(File.join(path, "*"))
        nested_directory_content = Dir.glob(File.join(path, "*/**/*"))
        [base_directory_content, nested_directory_content].flatten
      end

      # Copies all test suite files into the suites directory in the sandbox.
      #
      # @return [void]
      # @api private
      def prepare_pester_tests
        info("Preparing to copy files from  '#{suite_test_folder}' to the SUT.")
        sandboxed_suites_path = File.join(sandbox_path, "suites")
        copy_if_src_exists(suite_test_folder, sandboxed_suites_path)
      end

      # Copies PesterUtil.psm1 into the sandbox's modules folder, where the
      # updated $Env:PSModulePath will find it.
      #
      # @return [void]
      # @api private
      def prepare_supporting_psmodules
        info("Preparing to copy files from '#{support_psmodule_folder}' to the SUT.")
        sandbox_module_path = File.join(sandbox_path, "modules")
        copy_if_src_exists(support_psmodule_folder, sandbox_module_path)
      end

      # Copies a folder recursively, preserving its layers. Mostly used to
      # copy into the sandbox. Does nothing when the source does not exist.
      #
      # @param src_to_validate [String] folder to copy
      # @param destination [String] folder to copy into, created if missing
      # @return [void]
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

      # Returns the folder containing the test suites, falling back to
      # `test_base_path` when `test_folder` is not set.
      #
      # @return [String] path to the folder holding the suites
      # @api private
      def test_folder
        config[:test_folder].nil? ? config[:test_base_path] : absolute_test_folder
      end

      # Resolves `test_folder` to an absolute path, descending into an
      # `integration` subfolder when one exists.
      #
      # @return [String] absolute path to the folder holding the suites
      # @api private
      def absolute_test_folder
        path = (Pathname.new config[:test_folder]).realpath
        integration_path = File.join(path, "integration")
        Dir.exist?(integration_path) ? integration_path : path.to_s
      rescue Errno::ENOENT
        raise UserError, "The verifier's 'test_folder' is set to " \
                         "'#{config[:test_folder]}', which does not exist. It is resolved " \
                         "relative to the directory kitchen runs in, so give it a path that " \
                         "exists there or an absolute one."
      end

      # Returns the entries of a config option that is documented as a list.
      #
      # YAML makes it easy to write a single mapping where a list of mappings
      # was meant -- leaving off the leading `- ` is enough. `Array()` turns
      # such a mapping into a list of `[key, value]` pairs, which then renders
      # as nonsense PowerShell instead of failing, so reject it here where we
      # can still say which option is at fault.
      #
      # @param key [String] the option's name, for the error message
      # @param value [Object] the configured value
      # @return [Array] the entries to iterate over
      # @raise [Kitchen::UserError] when a single mapping was given
      # @api private
      def config_list(key, value)
        if value.is_a?(Hash)
          raise UserError, "The verifier's '#{key}' must be a list, but a single mapping " \
                           "was given. Put a '- ' in front of each entry in kitchen.yml."
        end

        Array(value)
      end

      # Returns the Name of a mapping-shaped entry in one of the module or
      # repository lists.
      #
      # The name becomes a PowerShell variable that the generated script splats,
      # so a missing one either blows up here or emits an empty `${}` that fails
      # on the instance a long way from its cause.
      #
      # @param key [String] the option's name, for the error message
      # @param entry [Hash] the entry to read the name from
      # @return [String] the entry's Name
      # @raise [Kitchen::UserError] when the entry is not a mapping, or has no
      #   usable Name
      # @api private
      def module_name!(key, entry)
        unless entry.is_a?(Hash)
          raise UserError, "Every entry under the verifier's '#{key}' must be a mapping with " \
                           "at least a 'Name'; #{entry.inspect} is a #{entry.class}."
        end

        name = entry[:Name] || entry["Name"]
        if name.to_s.empty?
          raise UserError, "Every mapping under the verifier's '#{key}' needs a 'Name'; " \
                           "#{entry.inspect} has none."
        end

        name.to_s
      end

      # Returns the final segment of a path that lives on the SUT.
      #
      # File.basename applies the *workstation's* separator rules, so a Windows
      # remote path such as 'C:\results\out.xml' comes back unchanged when
      # kitchen runs on macOS or Linux -- the usual case for a Windows SUT.
      # Split on either separator instead.
      #
      # @param path [String] a path as it exists on the instance
      # @return [String] the last path segment
      # @api private
      def remote_basename(path)
        path.to_s.split(%r{[\\/]}).last.to_s
      end

      # Returns a run of spaces of the given width, used to pad messages and
      # indent generated PowerShell hashtables.
      #
      # @param depth [Integer] number of spaces
      # @return [String] the padding
      # @api private
      def pad(depth = 0)
        " " * depth
      end
    end
  end
end
