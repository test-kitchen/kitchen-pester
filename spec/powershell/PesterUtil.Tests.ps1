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

# Unit tests for PesterUtil.psm1, the PowerShell module kitchen-pester ships to
# the system under test. It bootstraps modules before PowerShellGet is usable,
# so it runs on the least capable machines this verifier supports -- exactly
# where a mistake is most expensive and least visible.
#
# Nothing here touches the network or writes outside a temporary directory.

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '../../lib/support/modules/PesterUtil/PesterUtil.psm1' |
        Convert-Path
    Import-Module $script:ModulePath -Force
}

AfterAll {
    Remove-Module PesterUtil -Force -ErrorAction SilentlyContinue
}

Describe 'PesterUtil module' {
    It 'imports without error' {
        { Import-Module $script:ModulePath -Force } | Should -Not -Throw
    }

    It 'exports the three functions the verifier calls' {
        # The generated PowerShell calls Install-ModuleFromNuget and Set-PSRepo
        # by name, so renaming either silently breaks the SUT.
        $exported = (Get-Command -Module PesterUtil).Name
        $exported | Should -Contain 'Install-ModuleFromNuget'
        $exported | Should -Contain 'Set-PSRepo'
    }

    It 'enables TLS 1.2, which older Windows images need to reach the gallery' {
        $protocol = [Net.ServicePointManager]::SecurityProtocol
        ($protocol -band [Net.SecurityProtocolType]::Tls12) | Should -Not -Be 0
    }
}

Describe 'Set-PSRepo' {
    Context 'when the repository is already registered' {
        It 'updates it rather than registering a second time' {
            Mock -ModuleName PesterUtil Get-PSRepository { @{ Name = 'Internal' } }
            Mock -ModuleName PesterUtil Set-PSRepository { }
            Mock -ModuleName PesterUtil Register-PSRepository { }

            Set-PSRepo -Repository @{ Name = 'Internal' }

            Should -ModuleName PesterUtil -Invoke Set-PSRepository -Times 1 -Exactly
            Should -ModuleName PesterUtil -Invoke Register-PSRepository -Times 0 -Exactly
        }

        It 'splats every key of the repository definition' {
            Mock -ModuleName PesterUtil Get-PSRepository { @{ Name = 'Internal' } }
            Mock -ModuleName PesterUtil Set-PSRepository { }

            Set-PSRepo -Repository @{
                Name               = 'Internal'
                SourceLocation     = 'https://proget.example/nuget'
                InstallationPolicy = 'Trusted'
            }

            Should -ModuleName PesterUtil -Invoke Set-PSRepository -Times 1 -Exactly -ParameterFilter {
                $Name -eq 'Internal' -and
                $SourceLocation -eq 'https://proget.example/nuget' -and
                $InstallationPolicy -eq 'Trusted'
            }
        }
    }

    Context 'when the repository is not yet registered' {
        It 'registers it' {
            Mock -ModuleName PesterUtil Get-PSRepository { $null }
            Mock -ModuleName PesterUtil Set-PSRepository { }
            Mock -ModuleName PesterUtil Register-PSRepository { }

            Set-PSRepo -Repository @{
                Name           = 'Internal'
                SourceLocation = 'https://proget.example/nuget'
            }

            Should -ModuleName PesterUtil -Invoke Register-PSRepository -Times 1 -Exactly
            Should -ModuleName PesterUtil -Invoke Set-PSRepository -Times 0 -Exactly
        }
    }

    Context 'on an old PowerShellGet that has no *-PSRepository cmdlets' {
        BeforeEach {
            # Only Get-PSRepository is missing; the PackageSource family stands in.
            Mock -ModuleName PesterUtil Get-Command {
                if ($args -contains 'Get-PSRepository' -or $Name -eq 'Get-PSRepository') { $null }
                else { [pscustomobject]@{ Name = 'stub' } }
            }
        }

        It 'falls back to Set-PackageSource for a source that exists' {
            Mock -ModuleName PesterUtil Get-PackageSource { @{ Name = 'Internal' } }
            Mock -ModuleName PesterUtil Set-PackageSource { }
            Mock -ModuleName PesterUtil Register-PackageSource { }

            Set-PSRepo -Repository @{ Name = 'Internal' }

            Should -ModuleName PesterUtil -Invoke Set-PackageSource -Times 1 -Exactly
            Should -ModuleName PesterUtil -Invoke Register-PackageSource -Times 0 -Exactly
        }

        It 'falls back to Register-PackageSource for a source that does not' {
            Mock -ModuleName PesterUtil Get-PackageSource { $null }
            Mock -ModuleName PesterUtil Set-PackageSource { }
            Mock -ModuleName PesterUtil Register-PackageSource { }

            Set-PSRepo -Repository @{ Name = 'Internal' }

            Should -ModuleName PesterUtil -Invoke Register-PackageSource -Times 1 -Exactly
            Should -ModuleName PesterUtil -Invoke Set-PackageSource -Times 0 -Exactly
        }
    }

    Context 'when neither cmdlet family is available' {
        It 'throws rather than failing silently' {
            Mock -ModuleName PesterUtil Get-Command { $null }

            { Set-PSRepo -Repository @{ Name = 'Internal' } } |
                Should -Throw '*Cannot Set PS Repository*'
        }
    }
}

Describe 'Install-ModuleFromNuget' {
    BeforeEach {
        # Replace the WebClient so nothing here can reach the network. The stub
        # throws with the URL it was handed, which is also how these tests
        # observe the URL the function built.
        Mock -ModuleName PesterUtil New-Object -ParameterFilter {
            $TypeName -eq 'system.net.webclient'
        } -MockWith {
            $stub = [pscustomobject]@{ Proxy = $null }
            $stub | Add-Member -MemberType ScriptMethod -Name DownloadFile -Value {
                param($uri, $path)
                throw "network blocked, asked for: $uri"
            }
            $stub
        }
        Mock -ModuleName PesterUtil New-Item { }
        Mock -ModuleName PesterUtil Expand-Archive { }
        Mock -ModuleName PesterUtil Remove-Item { }
    }

    Context 'building the download URL' {
        BeforeEach {
            Mock -ModuleName PesterUtil Test-Path { $false }
        }

        It 'joins the gallery URL, module name and version' {
            { Install-ModuleFromNuget -Module @{ Name = 'PowerShellGet'; Version = '2.2.5' } `
                -GalleryUrl 'https://gallery.invalid/api/v2' } |
                Should -Throw '*gallery.invalid/api/v2/package/PowerShellGet/2.2.5*'
        }

        It 'does not double the slash when the gallery URL has a trailing one' {
            { Install-ModuleFromNuget -Module @{ Name = 'PowerShellGet'; Version = '2.2.5' } `
                -GalleryUrl 'https://gallery.invalid/api/v2/' } |
                Should -Throw '*gallery.invalid/api/v2/package/PowerShellGet/2.2.5*'
        }

        It 'defaults to the public PowerShell Gallery' {
            { Install-ModuleFromNuget -Module @{ Name = 'Pester'; Version = '5.5.0' } } |
                Should -Throw '*powershellgallery.com/api/v2/package/Pester/5.5.0*'
        }

        It 'never reaches the network' {
            { Install-ModuleFromNuget -Module @{ Name = 'Pester'; Version = '5.5.0' } } | Should -Throw
            Should -ModuleName PesterUtil -Invoke New-Object -Times 1 -Exactly -ParameterFilter {
                $TypeName -eq 'system.net.webclient'
            }
        }
    }

    Context 'when the requested version is already installed' {
        It 'returns without downloading' {
            Mock -ModuleName PesterUtil Test-Path { $true }

            Install-ModuleFromNuget -Module @{ Name = 'Pester'; Version = '5.5.0' }

            Should -ModuleName PesterUtil -Invoke New-Object -Times 0 -Exactly
            Should -ModuleName PesterUtil -Invoke Expand-Archive -Times 0 -Exactly
        }
    }

    Context 'pre-release versions' {
        It 'strips the pre-release suffix when choosing the on-disk folder' {
            # 5.6.0-alpha1 has to land in a folder named 5.6.0, which is what
            # PowerShell module resolution looks for.
            Mock -ModuleName PesterUtil Test-Path -MockWith { $Path -like '*5.6.0' }

            Install-ModuleFromNuget -Module @{ Name = 'Pester'; Version = '5.6.0-alpha1' }

            Should -ModuleName PesterUtil -Invoke Test-Path -ParameterFilter { $Path -like '*5.6.0' }
            Should -ModuleName PesterUtil -Invoke New-Object -Times 0 -Exactly
        }
    }

    Context 'proxy configuration' {
        BeforeEach {
            Mock -ModuleName PesterUtil Test-Path { $false }
        }

        AfterEach {
            $env:HTTP_PROXY = $null
            $env:NO_PROXY = $null
        }

        It 'builds a WebProxy when HTTP_PROXY is set' {
            $env:HTTP_PROXY = 'http://proxy.invalid:8080'
            Mock -ModuleName PesterUtil New-Object -ParameterFilter {
                $TypeName -eq 'System.Net.WebProxy'
            } -MockWith { [pscustomobject]@{} }

            { Install-ModuleFromNuget -Module @{ Name = 'Pester'; Version = '5.5.0' } } | Should -Throw

            Should -ModuleName PesterUtil -Invoke New-Object -Times 1 -Exactly -ParameterFilter {
                $TypeName -eq 'System.Net.WebProxy'
            }
        }

        It 'passes NO_PROXY through when it is also set' {
            $env:HTTP_PROXY = 'http://proxy.invalid:8080'
            $env:NO_PROXY = 'internal.example'
            Mock -ModuleName PesterUtil New-Object -ParameterFilter {
                $TypeName -eq 'System.Net.WebProxy'
            } -MockWith { [pscustomobject]@{} }

            { Install-ModuleFromNuget -Module @{ Name = 'Pester'; Version = '5.5.0' } } | Should -Throw

            Should -ModuleName PesterUtil -Invoke New-Object -Times 1 -Exactly -ParameterFilter {
                $TypeName -eq 'System.Net.WebProxy' -and
                $ArgumentList -contains 'internal.example'
            }
        }
    }
}
