#! 
# https://www.sitepoint.com/creating-your-first-gem/
chef gem build $PSScriptRoot/kitchen-pester.gemspec

rm -Force ~/appdata/local/chefdk/gem/ruby/*/cache/kitchen-pester-*.gem
rm -Force ~/appdata/local/chefdk/gem/ruby/*/specifications/kitchen-dsc-*.gemspec
rm -Force ~/appdata/local/chefdk/gem/ruby/*/gems/kitchen-pester-* -Recurse

chef gem install (gi $PSScriptRoot/kitchen-pester-*.gem).Name
Get-Date
