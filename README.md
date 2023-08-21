# Kitchen::Pester

[![Build Status](https://dev.azure.com/test-kitchen/kitchen-pester/_apis/build/status/test-kitchen.kitchen-pester?branchName=main)](https://dev.azure.com/test-kitchen/kitchen-pester/_build/latest?definitionId=4&branchName=main)
[![Gem Version](https://badge.fury.io/rb/kitchen-pester.svg)](http://badge.fury.io/rb/kitchen-pester)

Execute [Pester](https://github.com/pester/Pester) tests, cross platform, right from Test-Kitchen, without having to transit the Busser layer.

For now, this gem hasn't been tested with Pester v5+.

## Usage

Either

```shell
gem install kitchen-pester
```

or include

```ruby
gem 'kitchen-pester'
```

in your Gemfile.

In your .kitchen.yml include

```yaml
verifier:
  name: pester
```

This can be a top-level declaration, a per-node declaration, or a per-suite declaration.

## Options

* `restart_winrm` - boolean, default is `false`. (Windows only)
Restarts the winrm service using a scheduled tasks before proceding.
This setting is ignored on non-windows OSes.

* `test_folder` - string, default is `./tests/integration/`.
Allows you to specify a custom path (the default is ./test/[integration/]) for your integration tests.
This can be an absolute path or relative to the root of the folder kitchen is running from on the host machine.
This path must exist.
When you specify a folder, it will automatically try to append `/integration` to that path.
If it exists, it will use this as the root tests directory.
If it doesn't, it will use the `test_folder`.
If you have a `helpers` folders under `test_folder` (i.e. `./tests/helpers`), those will be copied to the SUT for every test suite.

* `remove_builtin_powershellget` - bool, default is `true` (v.1.0.0.1)
Remove the built-in PowerShellGet and PackageManagement modules on Windows (v1.0.0.1), as they will often cause problems and will be superseded by the bootstrapped versions by default.

* `remove_builtin_pester` - bool, default is `true` (v3.4.0)
Remove the Pester module that is built-in on Windows (v3.4.0), because upgrading to a later version is awkward if this is not first removed (requires both `-SkipPublisherCheck` & `-Force`, which makes it slow every time you `kitchen verify`).
Removing the built-in ensures that the only version in use will be the Pester version specified by the configuration.

* `bootstrap` - map,  default is `{}` (PowershellGet & Package Management)
Allows kitchen-pester to download the PowerShellGet and PackageManagement module directly from the Nuget API URL.
Note that it needs to be able to download the nupkg from `$galleryUrl/package/PowerShellGet`, which may not be available with some private feed implementations.

* `register_repository` - array (of maps), default is `[]`
Allows you to register PSRepositories to download modules from. Useful when you want to use a private feed.
This expects a map for each repository to register, the values will be splatted to `Register-PSRepository` (or `Set-PSRepository` if it already exists).

  ```yaml
    register_repository:
      - Name: MyPrivateNuget
        SourceLocation: https://mypsrepo.local/api/v2
        InstallationPolicy: trusted
        PackageManagementProvider: Nuget
  ```

* `install_modules` - array (of maps), default is `[]`
Array of maps, that will be splatted to the Install-Module parameters.
Useful for installing dependencies from a gallery.

  ```yaml
    install_modules:
      - Name: MyModule
        Repository: MyPrivateRepo
        SkipPublisherCheck: true
  ```

* `copy_folders` - array, default is `[]`
Folders (relative to the current directory or absolute) to copy to the System Under Test (SUT).
The SUT's `$env:PSModulePath` will have the parent folder prepended for the session.
If you are testing a PowerShell module you have built as part of your build process, this enables you to copy the module folder directly to the target machine.

  ```yaml
  verifier:
    name: pester
    copy_folders:
      - output/MyModule
    pester_install:
      MaximumVersion: '4.99.999'
  ```

* `skip_pester_install` - bool default is `false`
Skip installing pester and just use what's available on the box, or what you have copied with the `copy_folders` options.

* `pester_install` - map, default is

  ```ruby
  {
    SkipPublisherCheck: true,
    Force: true,
    ErrorAction: "Stop",
  }
  ```

Specify parameters for installing Pester before running the tests.
The map will be splatted to the `Install-Module -Name Pester` command.
You can use this to install the module from a private gallery, for instance.

* `pester_configuration` - hash, defaults to

  ```ruby
  {
    run: {
      path: "suites/",
      PassThru: true,
    },
    TestResult: {
      Enabled: true,
      OutputPath: "PesterTestResults.xml",
      TestSuiteName: "",
    },
    Output: {
      Verbosity: "Detailed",
    }
  }
  ```

  This object is converted to a hashtable used to create a PesterConfiguration object in **Pester v5** (`$PesterConfig = New-PesterConfiguration -Hashtable $pester_configuration`), in turn used with invoke pester (`Invoke-Pester -Configuration $PesterConfig`).
  If some of the following **keys** are missing, the associated defaults below will be used:
  * **Run.Path** = `$Env:Temp/verifier/suites`
  * **TestResult.TestSuiteName** = `Pester - $KitchenInstanceName`
  * **TestResult.OutputPath** = `$Env:Temp/verifier/PesterTestResults.xml`

  If the installed version of Pester is **v4**, and the `pester_configuration` hash is provided, valid parameters for `Invoke-Pester` will be used (and invalid parameter names will be ignored).
  In the case of Pester v4, and the `pester_configuration` hash does not provide the keys for `Script`,`OutputFile`,`OutputFormat`, `Passthru`, `PesterOption`, the defaults will be:
  * Script: `$Env:Temp/verifier/suites`
  * OutPutFile: `$Env:Temp/verifier/PesterTestResults.xml`
  * OutputFormat: `NUnitXml`
  * Passthru: `true`
  * PesterOption: the result of `$(New-PesterOption -TestSuiteName "Pester - $KitchenInstanceName)`

* `shell` - string, default is `Nil` which makes it call PowerShell on Windows (Windows PowerShell), pwsh on other OSes.
It will honour the `sudo` configuration property if set to true on non-windows.

* `sudo` - bool, default is `false`. (non-windows only)
Execute all PowerShell calls as sudo.
This is necessary in certain cases, such as when `pwsh` is installed via `snap` and is only available via `sudo` unless you customise the system's configuration.

* `downloads`- map[string, string], defaults to `{"./PesterTestResults.xml" => "./testresults}"`.
Files to download from SUT to local system, used to download the pester results localy.
The key is the remote file to download, while the value is the destination.
  * The source can:
    * Be relative to the verifier folder (by default `$TEMP/verifier`)
    * Be absolute on the system (e.g. `/var/tmp/file.zip` or `C:\\Windows\\Temp\\file.zip`)
  * The destination can:
    * Include `%{instance_name}` to indicate the Test Kitchen instance name
    * Be a directory (ends in `/` or `\\`)
    * Be relative to the Current Working Directory
    * Be absolute

  ```yaml
  downloads:
      PesterTestResults.xml: "./output/testResults/"
      kitchen_cmd.ps1: "./output/testResults/"
  ```

* `environment` - map[string, string], defaults to `{}`.
Environment variables to set in SUT for your pester tests to access.

  ```yaml
  environment:
      API_KEY: api-key-here
      PUSH_URI: https://push.example.com
  ```

---

## Examples

### Default Windows 2019 Install

If you're testing on a default image of Windows Server 2019, you probably need to replace the builtin Pester module (v3.4.0), and replace the builtin PackageManagement and PowerShellGet to a more recent for the install to work.

Assuming your tests are written for Peter v4, here's a sample configuration:

```yaml
verifier:
  name: pester
  pester_install:
    MaximumVersion: '4.99.999'
  bootstrap: # installs modules from nuget feed by download and unzip.
    repository_url: "https://www.powershellgallery.com/api/v2"
    modules:
      - PackageManagement
      - PowerShellGet
```

### Default Azure Ubuntu 18.04 Install

Assuming you are using the AzureRM driver and a Ubuntu image, you may need to install pwsh before being able to execute any PowerShell code.
One way to achieve this is by using Test-Kitchen's lifecycle hooks to install it using the [snap](https://snapcraft.io/powershell) package management.

Then if your tests are written for Pester v4.x, make sure you specify a maximum version in the install.
As pwsh comes with a recent version of PowerShellGet, it is not necessary to bootstrap the PowerShell environment.
The `Install-Module` command should work out of the box.

```yaml
driver:
  name: azurerm
  subscription_id: <%= ENV['AZ_SUBSCRIPTION_ID'] %> # use a custom env variable
  location: 'westus2'
  machine_size: 'Standard_D2s_v3'

provisioner:
  name: shell # defaults to bash on linux, so the shebang is important!
  script: 'tests/integration/provisioning.ps1'

verifier:
  name: pester
  pester_install:
    MaximumVersion: '4.99.999'

platforms:
  - name: ubuntu-18.04
    driver:
      image_urn: Canonical:UbuntuServer:18.04-LTS:latest
    lifecycle:
      post_create:
      - remote: sudo snap install powershell --classic

suites:
  - name: default
```

### Windows 2012 R2 default install

If your image is a windows 2012 R2, you will be running on PowerShell v4.
Assuming that's what you want, but you still need Pester v4 instead of the built-in 3.4.0, you will need to remove the built-in version, bootsrap the PowerShellGet version to a more recent one, and finally install Pester to your desired version.

```yaml
verifier:
  name: pester
  pester_install:
    MaximumVersion: '4.99.999'
  bootstrap:
    repository_url: "https://www.powershellgallery.com/api/v2"
    modules:
      - PackageManagement
      - PowerShellGet
```

---

## Contributing

1. [Fork it](https://github.com/test-kitchen/kitchen-pester/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
