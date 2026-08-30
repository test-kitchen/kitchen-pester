# Contributing to kitchen-pester

Thanks for your interest in improving kitchen-pester. Bug reports, feature
requests, and pull requests are all welcome.

## Reporting issues

Report bugs and request features on the
[issue tracker](https://github.com/test-kitchen/kitchen-pester/issues). For
bugs, please include:

- the version of kitchen-pester and Test Kitchen you are using
- the Pester version on the system under test, and your platform
- your `kitchen.yml` verifier block
- the output of the failing command, ideally with `-l debug`

Because the verifier is largely a PowerShell string builder, the generated
script from a debug run is usually the most useful thing to attach.

## Submitting changes

1. [Fork it](https://github.com/test-kitchen/kitchen-pester/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Make your change, with tests
4. Make sure `bundle exec rake` passes
5. Push (`git push origin my-new-feature`)
6. Open a pull request

Please keep pull requests focused on a single change — it makes review much
faster. Update `README.md` when you add or change a verifier option.

## Testing

There are two layers: fast unit specs that run anywhere, and a slower
integration run that drives a real Windows SUT.

### Unit specs

```sh
bundle install
bundle exec rake unit    # specs
bundle exec rake style   # cookstyle/chefstyle, specs included
bundle exec rake         # both
```

The specs live in `spec/` and cover `Kitchen::Verifier::Pester` directly. The
verifier is almost entirely a PowerShell string builder, so they assert on the
script text it emits rather than standing up a VM. `spec/spec_helper.rb`
provides `build_verifier`, which wires a verifier to a real `Kitchen::Instance`
so `windows_os?`, `instance.name` and friends behave as they do in production.

`spec/kitchen/verifier/pester_syntax_spec.rb` feeds the generated scripts
through the real PowerShell parser to catch quoting and brace bugs. It skips
itself when `pwsh` is not on `PATH`; install
[PowerShell](https://github.com/PowerShell/PowerShell) to run it locally.

To run a single file:

```sh
bundle exec ruby -Ilib -Ispec spec/kitchen/verifier/pester_spec.rb
```

### PowerShell module specs

`lib/support/modules/PesterUtil/PesterUtil.psm1` is the PowerShell module
kitchen-pester copies to the system under test. It has its own Pester specs in
`spec/powershell/`:

```sh
bundle exec rake pester
```

They need `pwsh` and Pester 5+, and skip themselves when either is missing, so
`rake test` still works on a plain Ruby box. To run them locally:

```sh
pwsh -Command 'Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser'
```

Nothing in them touches the network — the `WebClient` is replaced with a stub
that throws the URL it was handed, which is also how the specs assert on the
URL that `Install-ModuleFromNuget` builds.

### Integration

Integration testing runs kitchen-pester through Test Kitchen itself, on a real
Windows SUT. `kitchen.windows.yml` drives it: the proxy driver points at
`localhost` over WinRM, `provision.ps1` prepares the environment, and the
verifier runs the tests under `tests/integration/<suite>/`.

There are two suites, because the verifier emits a different `Invoke-Pester`
dialect depending on the version it finds on the SUT:

| Suite | Pester | Branch it covers |
| --- | --- | --- |
| `default` | whatever the gallery ships, currently 5.x | `New-PesterConfiguration` |
| `pester4` | pinned with `pester_install.MaximumVersion` | loose `Invoke-Pester` parameters |

To run it against your own Windows machine, set `MACHINE_USER` and
`MACHINE_PASS` to an account that can log in over WinRM, then:

```sh
export KITCHEN_YAML=kitchen.windows.yml
bundle exec kitchen verify default
bundle exec kitchen verify pester4
```

Results land in `./testresults/<instance name>/PesterTestResults.xml`.

The `pester4` suite only tests what it claims to if Pester 5 is not also
installed machine-wide — `Import-Module Pester` takes the highest version it
can see. CI deletes the runner's pre-installed copy first, and the suite's
first assertion is that it really did run under Pester 4.

`.github/workflows/integration.yml` runs both suites on Windows Server 2022 and
2025, against the oldest and newest supported Ruby.

## Documentation

The public API is documented with [YARD](https://yardoc.org/). Every class,
module, constant and method carries a docstring.

```sh
bundle exec rake docs:generate   # build the HTML into doc/
bundle exec rake docs:coverage   # list anything that is undocumented
bundle exec rake yard            # same as docs:generate, with a stats summary
```

`docs:coverage` is there when you want it; it is not wired into `rake quality`
or CI.

Options live in `.yardopts`, so a bare `yard` on the command line produces the
same output as the rake task.
