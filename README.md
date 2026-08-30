# kitchen-pester

[![Gem Version](https://badge.fury.io/rb/kitchen-pester.svg)](http://badge.fury.io/rb/kitchen-pester)

Run [Pester](https://pester.dev/) tests against a machine that
[Test Kitchen](https://kitchen.ci/) built for you.

Test Kitchen creates the machine, your provisioner configures it, and
kitchen-pester copies your `*.Tests.ps1` files onto it, installs Pester, runs
the tests, and brings the results back. No Busser layer in between.

It works on Windows and on Linux or macOS instances with
[PowerShell](https://github.com/PowerShell/PowerShell) installed.

## Quick start

### 1. Install the gem

This verifier ships as part of [Cinc Workstation](https://cinc.sh/start/workstation/).
If you have Cinc Workstation installed, there is nothing else to install.

To install it into a standalone Ruby:

```bash
gem install kitchen-pester
```

or add it to your `Gemfile`:

```ruby
gem "kitchen-pester"
```

The examples below use the `cinc` commands. Everything here works identically
with Chef Workstation — see [Using with Chef](#using-with-chef).

### 2. Point Test Kitchen at it

In `kitchen.yml`:

```yaml
verifier:
  name: pester
```

You can set this at the top level, per platform, or per suite.

### 3. Put your tests where it will find them

For a suite named `default`, that is `tests/integration/default/`:

```text
tests/
└── integration/
    ├── default/
    │   └── myapp.Tests.ps1
    └── helpers/            # optional, copied to every suite
        └── Assertions.ps1
```

### 4. Write a test

An ordinary Pester file — nothing kitchen-specific:

```powershell
Describe 'myapp' {
  It 'installed the binary' {
    'C:\Program Files\myapp\myapp.exe' | Should -Exist
  }

  It 'is listening on 8080' {
    Get-NetTCPConnection -LocalPort 8080 | Should -Not -BeNullOrEmpty
  }
}
```

### 5. Run it

```bash
cinc kitchen verify
```

Results are written to `./testresults/PesterTestResults.xml` in NUnit format,
ready for a CI system to pick up. A failing Pester test fails `cinc kitchen verify`.

## How it works

Worth knowing when something goes wrong:

1. **Sandbox.** Your suite's tests, any `helpers/`, anything in `copy_folders`,
   and kitchen-pester's own `PesterUtil` PowerShell module are staged into a
   local temp directory.
2. **Transfer.** Test Kitchen ships that sandbox to the instance, under
   `$env:TEMP/verifier` on Windows or `/tmp/verifier` elsewhere.
3. **Prepare.** kitchen-pester prepends the sandbox's `modules/` folder to
   `$env:PSModulePath`, then installs Pester and anything in
   `install_modules`.
4. **Run.** It writes a `kitchen_cmd.ps1` on the instance and invokes it. Your
   tests run from the `suites/` folder inside the sandbox.
5. **Download.** Everything in `downloads` is copied back — including when the
   run fails, so you always get the results file.

Every step is generated PowerShell. If a run misbehaves, `kitchen_cmd.ps1` on
the instance is the exact script that ran.

## Pester versions

kitchen-pester supports **Pester 5 and later** (the default) and **Pester 4**.

It detects the installed version on the instance and adapts: Pester 5 and
later get a `PesterConfiguration` object built from your
`pester_configuration`, Pester 4 and earlier get loose `Invoke-Pester`
parameters. You do not need to tell it which one you are on.

To stay on Pester 4, cap the install. `pester_install` is
[replaced, not merged](#map-options-are-replaced-not-merged), so repeat the
defaults you still want — without `SkipPublisherCheck` the install fails
against the Pester that ships with Windows:

```yaml
verifier:
  name: pester
  pester_install:
    MaximumVersion: '4.99.999'
    SkipPublisherCheck: true
    Force: true
    ErrorAction: Stop
```

## Configuration

All of these go under `verifier:` in `kitchen.yml`.

### Map options are replaced, not merged

Every option below whose type is **map** — `pester_install`,
`pester_configuration`, `bootstrap`, `environment`, `downloads` — replaces its
default outright. A plugin default applies only when the key is absent
altogether, so setting one key inside one of these maps discards every other
key the default supplied. (Merging between the top-level, platform and suite
`verifier:` blocks is unaffected — that part is a deep merge.)

This bites hardest on `pester_install` and `pester_configuration`, where the
discarded defaults are the ones that produce the results file. Whenever you set
a map option, write out the whole map, taking the defaults from the tables
below as your starting point.

### Common

| Option | Type | Default | What it does |
| --- | --- | --- | --- |
| `test_folder` | string | `tests` | Where your tests live. See [Test discovery](#test-discovery). |
| `downloads` | map | `{"./PesterTestResults.xml" => "./testresults/"}` | Files to copy back from the instance. See [Downloads](#downloads). |
| `environment` | map | `{}` | Environment variables to set for your tests. |
| `copy_folders` | array | `[]` | Local folders to copy to the instance and put on `$env:PSModulePath`. |
| `pester_configuration` | map | see [below](#pester_configuration) | Passed through to Pester. |
| `root_path` | string | driver default | Directory on the SUT the sandbox is copied into. Relative `copy_folders` sources and the `suites` directory resolve against it, and `PesterTestResults.xml` is written there. |
| `suite_name` | string | the suite name | Name of the suite, used when locating its tests. |

### Installing Pester and its dependencies

| Option | Type | Default | What it does |
| --- | --- | --- | --- |
| `pester_install` | map | `{SkipPublisherCheck: true, Force: true, ErrorAction: "Stop"}` | Splatted to `Install-Module -Name Pester`. |
| `skip_pester_install` | bool | `false` | Use whatever Pester is already on the box. |
| `install_modules` | array | `[]` | Extra modules to install from a gallery. |
| `register_repository` | array | `[]` | PSRepositories to register first, for private feeds. |
| `bootstrap` | map | `{repository_url: "https://www.powershellgallery.com/api/v2", modules: []}` | Modules to fetch straight from a NuGet feed, before PowerShellGet is usable. |
| `remove_builtin_pester` | bool | `true` | Remove the Pester 3.4.0 that ships with Windows. |
| `remove_builtin_powershellget` | bool | `true` | Remove the PowerShellGet and PackageManagement 1.0.0.1 that ship with Windows. |

### Platform and shell

| Option | Type | Default | What it does |
| --- | --- | --- | --- |
| `shell` | string | `nil` | Shell binary to use. Defaults to `powershell` on Windows, `pwsh` elsewhere. |
| `sudo` | bool | `false` | Run PowerShell under sudo. Non-Windows only. |
| `restart_winrm` | bool | `false` | Restart WinRM via a scheduled task before verifying. Windows only. |

### Test discovery

`test_folder` is where kitchen-pester starts looking. It may be relative to
the directory you run `kitchen` from, or absolute, and it must exist.

If `<test_folder>/integration` exists, that becomes the root instead — which is
why the default `tests` finds `tests/integration`. Within that root:

- `<root>/<suite_name>/` is copied to the instance and is what Pester runs.
  Nest files however you like; Pester recurses.
- `<root>/helpers/` is copied alongside **every** suite.

### Downloads

The key is the file on the instance, the value is where to put it locally.

The **source** may be relative to the verifier folder (`$env:TEMP/verifier` by
default) or absolute (`/var/tmp/file.zip`, `C:\Windows\Temp\file.zip`).

The **destination** may be relative to the current directory or absolute, may
end in `/` or `\` to mean "a directory, keep the filename", and may contain
`%{instance_name}` to keep results from different instances apart:

```yaml
verifier:
  name: pester
  downloads:
    PesterTestResults.xml: "testresults/%{instance_name}/"
    kitchen_cmd.ps1: "testresults/%{instance_name}/"
```

Downloading `kitchen_cmd.ps1` like that is a useful debugging trick: it is the
generated script that actually ran.

### pester_configuration

Defaults to:

```yaml
run:
  path: "."
  PassThru: true
TestResult:
  Enabled: true
  OutputPath: PesterTestResults.xml
  TestSuiteName: ""
Output:
  Verbosity: Detailed
```

This map is [replaced, not merged](#map-options-are-replaced-not-merged), and
the defaults it replaces are load-bearing. `New-PesterConfiguration` defaults
both `TestResult.Enabled` and `Run.PassThru` to `$false`, so this:

```yaml
verifier:
  name: pester
  pester_configuration:
    Output:
      Verbosity: Diagnostic
```

turns off the NUnit results file — your `downloads` then have nothing to
fetch — and leaves the run without a result object to count failures from.
Copy the whole default map and edit the key you came for.

**On Pester 5**, this becomes a `PesterConfiguration` via
`New-PesterConfiguration -Hashtable`. Three keys are filled in for you if you
leave them unset:

| Key | Filled in with |
| --- | --- |
| `Run.Path` | `$env:TEMP/verifier/suites` |
| `TestResult.TestSuiteName` | `Pester - <kitchen instance name>` |
| `TestResult.OutputPath` | `$env:TEMP/verifier/PesterTestResults.xml` |

**On Pester 4**, keys matching a real `Invoke-Pester` parameter are used and
the rest are ignored. These defaults apply unless you set them:

| Parameter | Default |
| --- | --- |
| `Script` | `$env:TEMP/verifier/suites` |
| `OutputFile` | `$env:TEMP/verifier/PesterTestResults.xml` |
| `OutputFormat` | `NUnitXml` |
| `PassThru` | `true` |
| `PesterOption` | `New-PesterOption -TestSuiteName "Pester - <instance name>"` |

### register_repository

Each entry is splatted to `Register-PSRepository`, or `Set-PSRepository` if the
repository already exists:

```yaml
verifier:
  name: pester
  register_repository:
    - Name: MyPrivateNuget
      SourceLocation: https://mypsrepo.local/api/v2
      InstallationPolicy: trusted
      PackageManagementProvider: Nuget
```

### install_modules

Plain names, or maps splatted to `Install-Module`:

```yaml
verifier:
  name: pester
  install_modules:
    - PSScriptAnalyzer
    - Name: MyModule
      Repository: MyPrivateRepo
      SkipPublisherCheck: true
```

### bootstrap

For machines where PowerShellGet is too old to install anything — notably a
stock Windows image. Modules are downloaded and unzipped straight from the
NuGet API, bypassing `Install-Module` entirely.

The feed must serve `$repository_url/package/<ModuleName>`, which some private
feed implementations do not.

```yaml
verifier:
  name: pester
  bootstrap:
    repository_url: https://www.powershellgallery.com/api/v2
    modules:
      - PackageManagement
      - PowerShellGet
```

> **Note:** this key is
> [replaced, not merged](#map-options-are-replaced-not-merged). If you set
> `modules`, set `repository_url` too.

## Examples

### Testing a PowerShell module you just built

`copy_folders` puts your build output on the instance's `$env:PSModulePath`,
so your tests can `Import-Module MyModule` as if it were installed:

```yaml
verifier:
  name: pester
  copy_folders:
    - output/MyModule
  downloads:
    PesterTestResults.xml: "testresults/%{instance_name}/"
```

### A stock Windows image

Windows ships Pester 3.4.0 and PowerShellGet 1.0.0.1, neither of which can
install a modern Pester on its own. The defaults already remove both; bootstrap
replacements from NuGet so the install has something to work with:

```yaml
verifier:
  name: pester
  bootstrap:
    repository_url: https://www.powershellgallery.com/api/v2
    modules:
      - PackageManagement
      - PowerShellGet
```

### Linux, with PowerShell installed on the fly

Use Test Kitchen's lifecycle hooks to install `pwsh` after the machine comes
up. A recent `pwsh` ships a usable PowerShellGet, so no bootstrap is needed:

```yaml
provisioner:
  name: shell
  script: tests/integration/provisioning.ps1

verifier:
  name: pester

platforms:
  - name: ubuntu-22.04
    lifecycle:
      post_create:
        - remote: sudo snap install powershell --classic

suites:
  - name: default
```

If `pwsh` is only reachable through sudo — as with a snap install on some
systems — add `sudo: true` to the verifier.

### Passing secrets and settings to your tests

```yaml
verifier:
  name: pester
  environment:
    API_KEY: <%= ENV['API_KEY'] %>
    PUSH_URI: https://push.example.com
```

```powershell
Describe 'configuration' {
  It 'received the API key' {
    $env:API_KEY | Should -Not -BeNullOrEmpty
  }
}
```

## Troubleshooting

**`cinc kitchen verify` fails but I get no results file.** You should still get one
— downloads run even when the verify fails. If the file is missing, the run
died before Pester started; check the `cinc kitchen verify` output for the install
step.

**I set one `pester_configuration` key and the results file stopped appearing.**
Map options replace their default rather than merging into it, and the default
is what enables the results file. See
[Map options are replaced, not merged](#map-options-are-replaced-not-merged).

**I want to see the script that ran.** Add `kitchen_cmd.ps1` to `downloads`,
or look for it in `$env:TEMP/verifier` on the instance.

**`Install-Module` cannot find a repository.** The built-in PowerShellGet was
removed (the default) and nothing replaced it. Either `bootstrap` a newer
PowerShellGet, or set `remove_builtin_powershellget: false` if the machine's
own copy works.

**Tests are not found.** Check that your files are under
`<test_folder>/integration/<suite_name>/` and match Pester's discovery
pattern (`*.Tests.ps1`), and that the suite name in `kitchen.yml` matches the
folder name.

**PowerShell is not installed on a Linux instance.** kitchen-pester does not
install it. Use a lifecycle hook or your provisioner.

## Using with Chef

This verifier runs Pester and does not depend on Cinc or Chef being installed on
the system under test — it works with any Test Kitchen driver and provisioner.

The examples above use [Cinc Workstation](https://cinc.sh/start/workstation/) and
the `cinc kitchen` commands. With
[Chef Workstation](https://www.chef.io/downloads/tools/workstation) run `kitchen`
instead of `cinc kitchen`. No verifier configuration changes are needed.

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/test-kitchen/kitchen-pester). See
[CONTRIBUTING.md](CONTRIBUTING.md) for development setup, how to run the unit
specs, the PowerShell module specs, and the integration suite, and how the
documentation is generated.

## License

MIT. See [LICENSE](LICENSE).
