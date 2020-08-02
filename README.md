[![Build Status](https://dev.azure.com/test-kitchen/kitchen-pester/_apis/build/status/test-kitchen.kitchen-pester?branchName=master)](https://dev.azure.com/test-kitchen/kitchen-pester/_build/latest?definitionId=4&branchName=master)
[![Gem Version](https://badge.fury.io/rb/kitchen-pester.svg)](http://badge.fury.io/rb/kitchen-pester)

# Kitchen::Pester

Execute [Pester](https://github.com/pester/Pester) tests, cross platform, right from Test-Kitchen, without having to transit the Busser layer.

For now, this gem hasn't been tested with Pester v5+.

## Usage

Either
```
gem install kitchen-pester
```
or include
```
gem 'kitchen-pester'
```
in your Gemfile.

In your .kitchen.yml include
```yaml
verifier:
  name: pester
```
This can be a top-level declaration, a per-node declaration, or a per-suite declaration.

### Options

* `restart_winrm` - boolean, default is `false`. (Windows only)
* `test_folder` - string, default is `./tests/integration/`.
* `remove_builtin_powershellget` - bool, default is `true`
* `remove_builtin_pester` - bool, default is `true`
* `bootstrap` - hash,  default is `{}` (PowershellGet & Package Management)
* `register_repository` - hash, default is `[]`
* `use_local_pester_module` - bool default is `false`
* `pester_install` - hash, default is
  ```ruby
  {
    SkipPublisherCheck: true,
    Force: true,
    ErrorAction: "Stop",
  }
  ```
  (parameters for `Install-Module`)
* `install_modules` - array, default is `[]`
* `downloads` - hash, default is  `["./PesterTestResults.xml"] => "./testresults"`
* `copy_folders` - array, default is `[]`
* `sudo` - bool, default is `true`. (non-windows only)
* `downloads`- map[string, string], defaults to `["./PesterTestResults.xml"] => "./testresults"`. 


## Options explained

* `restart_winrm` - boolean, default is `false`. (Windows only)  
Restarts the winrm service using a scheduled tasks before proceding.

* `test_folder` - string, default is `./tests/integration/`.  
Allows you to specify a custom path (the default is ./test/[integration/]) for your integration tests.  This can be an absolute path or relative to the root of the folder kitchen is running from.  This path must exist.  
When you specify a folder, it will automatically try to append `/integration` to that path. If it exists, it will use this

* `remove_builtin_powershellget` - bool, default is `true` (v.1.0.0.1)  
Removes PowerShellGet and PackageManagement v1.0.0.1 are they cause issues with current version of the gallery.

* `remove_builtin_pester` - bool, default is `true` (v3.4.0)  
Remove the Pester module that is built-in Windows (v3.4.0) because upgrading o a later version is painful (SkipPublisherCheck & Force, which makes it slow every time you `kitchen verify`).

* `bootstrap` - hash,  default is `{}` (PowershellGet & Package Management)  
Allows to download the PowerShellGet and PackageManagement module without dependency, using the Nuget API URL. Note that it needs to be able to download the nupkg from `$galleryUrl/package/PowerShellGet`, which may not be available with some private feed implementation.

* `register_repository` - array (of hashes), default is `[]`  
Allows you to register PSRepositories to download modules from. Useful when you want to use a private feed.  
This expects a hash for each repository to register, the values will be splatted to `Register-PSRepository` (or `Set-PSRepository` if it already exists).

* `install_modules` - array (of hashes), default is `[]`  
Array of hashes, that will be splatted to the Install-Module parameters.
Useful for installing dependencies from a gallery.  
  ```yaml
    install_modules:
      - Name: MyModule
        Repository: MyPrivateRepo
        SkipPublisherCheck: true
  ```

* `copy_folders` - array, default is `[]`  
Folders (relative to the current directory or absolute) to copy to the System Under test (SUT). The SUT's `$Env:PSModulePath` will be changed for for the session to prepend the parent folder.
If you are testing a PowerShell module you have built as part of your build process, this enables you to copy this modules.
  ```yaml
  verifier:
    name: pester
    copy_folders:
      - output/MyModule
    pester_install:
      MaximumVersion: '4.99.999'
  ```

* `use_local_pester_module` - bool default is `false`  
Skip installing pester and just use what's available on the box, or what you have copied with the `copy_folders` options.


* `pester_install` - hash, default is
  ```ruby
  {
    SkipPublisherCheck: true,
    Force: true,
    ErrorAction: "Stop",
  }
  ```
  Specify parameters for installing Pester before running the tests. The hash will be splatted to the `Install-Module -Name Pester` command.
  You can use this to install from a private gallery for instance.

* `downloads` - hash, default is  `["./PesterTestResults.xml"] => "./testresults"`

* `sudo` - bool, default is `true`. (non-windows only)
execute all PowerShell calls as sudo. This is useful in some cases, such as when `pwsh` is installed via `snap` and is only available via `sudo` unless you customise the system's configuration.

* `downloads`- map[string, string], defaults to `["./PesterTestResults.xml"] => "./testresults"`.   
Files to download from SUT to local system, used to download the pester results locally. The key is the remote file, value the local file it should be saved as.

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
One way to achieve this is by using Test-Kitchen's lifecycle hooks to install is using the [snap](https://snapcraft.io/powershell) package management.

Then if your tests are written for Pester v4.x, make sure you specify a maximum version in the install.  
As pwsh comes with a recent version of PowerShellGet, it is not necessary to bootstrap the PowerShell environment. The `Install-Module` command should work out of the box.

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

1. Fork it ( https://github.com/[my-github-username]/kitchen-pester/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
