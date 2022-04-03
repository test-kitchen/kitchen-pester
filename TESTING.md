# Local testing of kitchen-pester

Testing of `kitchen-pester` is done via `kitchen-pester` in `test-kitchen`.

The `provision.ps1` file is used to prepare the environment, then tests are run in `test/integration/default/pester/default.tests.ps1`.

The general steps to test your changes:

1. Build new gem: `chef gem build ./kitchen-pester.gemspec`
1. Install built gem: `chef gem install ./kitchen-pester-<version>.gem`
1. Test with `test-kitchen`: `kitchen test`
1. Ensure that `PesterTestResults.xml` is created in `./testresults/default-windows-2016`
