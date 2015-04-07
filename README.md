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

## Contributing

1. Fork it ( https://github.com/[my-github-username]/kitchen-pester/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
