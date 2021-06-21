param (
    [Parameter()]
    [String[]]
    $FilesAndFoldersToClean = @(
        '~/appdata/local/chefdk/gem/ruby/*/cache/kitchen-pester-*.gem'
        '~/appdata/local/chefdk/gem/ruby/*/specifications/kitchen-dsc-*.gemspec'
        '~/appdata/local/chefdk/gem/ruby/*/gems/kitchen-pester-*'
        'C:\tools\ruby30\lib\ruby\gems\*\cache\kitchen-pester-*.gem'
        'C:\tools\ruby30\lib\ruby\gems\*\gems\kitchen-pester-*'
        'C:\tools\ruby30\lib\ruby\gems\*\specifications\kitchen-pester-*.gemspec'
    )
)
#! 
# https://www.sitepoint.com/creating-your-first-gem/
gem build $PSScriptRoot/kitchen-pester.gemspec

$FilesAndFoldersToClean | ForEach-Object -Process {
    Remove-Item -ErrorAction SilentlyContinue -Force -Recurse -Path $_
}


Get-Date
gem install (Get-Item -Path $PSScriptRoot/kitchen-pester-*.gem).Name
