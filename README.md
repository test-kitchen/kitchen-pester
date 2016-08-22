[![Gem Version](https://badge.fury.io/rb/kitchen-pester.svg)](http://badge.fury.io/rb/kitchen-pester)
# Kitchen::Pester

Execute [Pester](https://github.com/pester/Pester) tests right from Test-Kitchen, without having to transit the Busser layer.

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
```
verifier:
  name: pester
```
This can be a top-level declaration, a per-node declaration, or a per-suite declaration.

### Options

* `restart_winrm` - boolean, default is false.  This is primarily to support powershell v2 scenarios.  If Pester is not being found, enable this option.
* `test_folder` - string, default is nil.  `test-folder` allows you to specify a custom path (the default is ./test/integration/) for your integration tests.  This can be an absolute path or relative to the root of the folder kitchen is running from.  This path must exist.
* `copy_helpers` - boolean, default is false. This will copy the contents of ./test/integration/helpers/ which can be helpful for shared tests. 

## Contributing

1. Fork it ( https://github.com/[my-github-username]/kitchen-pester/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
