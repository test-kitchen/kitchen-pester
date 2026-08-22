# Copyright (c) 2015 Steven Murawski
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

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
