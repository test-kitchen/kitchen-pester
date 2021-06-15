#! 
# https://www.sitepoint.com/creating-your-first-gem/
gem build $PSScriptRoot/kitchen-pester.gemspec

rm -EA SilentlyContinue -Force ~/appdata/local/chefdk/gem/ruby/*/cache/kitchen-pester-*.gem
rm -EA SilentlyContinue -Force ~/appdata/local/chefdk/gem/ruby/*/specifications/kitchen-dsc-*.gemspec
rm -EA SilentlyContinue -Force ~/appdata/local/chefdk/gem/ruby/*/gems/kitchen-pester-* -Recurse

rm -EA SilentlyContinue -Force C:\tools\ruby30\lib\ruby\gems\*\cache\kitchen-pester-*.gem
rm -EA SilentlyContinue -Force C:\tools\ruby30\lib\ruby\gems\*\gems\kitchen-pester- -Recurse
rm -EA SilentlyContinue -Force C:\tools\ruby30\lib\ruby\gems\*\specifications\kitchen-pester-*.gemspec

Get-Date
gem install (gi $PSScriptRoot/kitchen-pester-*.gem).Name