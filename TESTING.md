# Testing kitchen-pester

There are two layers: fast unit specs that run anywhere, and a slower
integration run that drives a real Windows SUT.

## Unit specs

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

## PowerShell module specs

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

## Integration

Integration testing runs `kitchen-pester` through `test-kitchen` itself.
`provision.ps1` prepares the environment, then the tests in
`tests/integration/default/pester/default.tests.ps1` are run.

1. Build the gem: `chef gem build ./kitchen-pester.gemspec`
1. Install it: `chef gem install ./kitchen-pester-<version>.gem`
1. Run it: `kitchen test`
1. Confirm `PesterTestResults.xml` appears in `./testresults/default-windows-2016`

CI runs this on `windows-latest` via `.github/workflows/integration.yml`.
