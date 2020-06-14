[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Confirm-Directory {
    [CmdletBinding()]
    param($Path)

    $Item = if (Test-Path $Path) {
        Get-Item -Path $Path
    }
    else {
        New-Item -Path $Path -ItemType Directory
    }

    $Item.FullName
}

function Test-Module {
    [CmdletBinding()]
    param($Name)

    @(Get-Module -Name $Name -ListAvailable -ErrorAction SilentlyContinue).Count -gt 0
}

function Install-ModuleFromNuget {
    param (
        $Module,
        $GalleryUrl         = 'https://www.powershellgallery.com/api/v2'
    )

    $tempPath       = [io.path]::GetTempPath()
    $zipFileName    = "{0}.{1}.{2}" -f $Module.Name, $Module.Version, 'zip'
    $downloadedZip  = Join-Path -Path $tempPath $zipFileName
    $ModulePath     = Join-Path -Path $PSHome -ChildPath 'Modules'
    $ModuleFolder   = Join-Path -Path $ModulePath -ChildPath $Module.Name
    if ((Test-Path $ModuleFolder) -and ($PSVersionTable.PSVersion.Major -lt 5 -or $module.Force)) {
        # Check if available version is correct
        $ModuleManifest = (Join-Path -Path $ModuleFolder -ChildPath "$($Module.Name).psd1")
        if ((Test-Path -Path $ModuleManifest) -and -not $Module.Force) {
            # Import-PowerShellDataFile only exists since 5.1
            $ManifestInfo = Import-LocalizedData -BaseDirectory (Split-Path -Parent -Path $ModuleManifest) -FileName $Module.Name
            $ModuleVersionNoPreRelease = $Module.Version -replace '-.*',''
            # Compare the version in manifest with version required without Pre-release
            if ($ManifestInfo.ModuleVersion -eq $ModuleVersionNoPreRelease) {
                Write-Host "Module $($Module.Name) already installed, skipping."
                return
            }
            else {
                Write-Host "Module $($Module.Name) found with version '$($ManifestInfo.ModuleVersion)', expecting '$ModuleVersionNoPreRelease'."
            }
        }
        else {
            # if incorrect, remove it before install
            Remove-Item -Recurse -Force -Path $ModuleFolder
        }
    }
    elseif ($PSVersionTable.PSVersion.Major -gt 5) {
        # skip if the version already exists or if force is enabled
        $ModuleVersionNoPreRelease = $Module.Version -replace '-.*',''
        $ModuleFolder  = Join-Path -Path $ModuleFolder -ChildPath $ModuleVersionNoPreRelease
        if (-not $Module.Force -and (Test-Path -Path $ModuleFolder)) {
            Write-Verbose -Message "Module already installed."
            return
        }
    }

    if (-not (Test-Path $ModuleFolder)) {
        $null = New-Item -Path $ModuleFolder -force -ItemType Directory
    }

    $urlSuffix = "/package/$($Module.Name)/$($Module.Version)"
    $nupkgUrl = $GalleryUrl.TrimEnd('/') + '/' + $urlSuffix.Trim('/')
    $wc = New-Object 'system.net.webclient'
    Write-Verbose -Object "Downloading Package from $nupkgUrl" 
    $wc.DownloadFile($nupkgUrl,$downloadedZip)
    if (-not (Test-Path -Path $downloadedZip)) {
        Throw "Error trying to download nupkg '$nupkgUrl' to '$downloadedZip'."
    }
    
    # Test to see if Expand-Archive is available first
    if (Get-Command Expand-Archive) {
        Expand-Archive -Path $downloadedZip -DestinationPath $ModuleFolder -Force
    }
    else {
        # Fall back to COM object for Shell.Application zip extraction
        Write-Host "Creating COM object for zip file '$downloadedZip'."
        $shellcom = New-Object -ComObject Shell.Application
        $zipcomobject = $shellcom.Namespace($downloadedZip)
        $destination = $shellcom.Namespace($ModuleFolder)
        $destination.CopyHere($zipcomobject.Items(), 0x610)
        Write-Host "Nupkg installed at $ModuleFolder"
    }
}

# $VerifierModulePath = Confirm-Directory -Path (Join-Path #{config[:root_path]} -ChildPath 'modules')
# $VerifierDownloadPath = Confirm-Directory -Path (Join-Path #{config[:root_path]} -ChildPath 'pester')

# $env:PSModulePath = "$VerifierModulePath;$PSModulePath"

# if (-not (Test-Module -Name Pester)) {
#     if (Test-Module -Name PowerShellGet) {
#         Import-Module PowerShellGet -Force
#         Import-Module PackageManagement -Force

#         Get-PackageProvider -Name NuGet -Force > $null

#         Install-Module Pester -Force
#     }
#     else {
#         if (-not (Test-Module -Name PsGet)){ # We should get rid of this. 
#             # installing PSGet from someone we don't know's github raw is scary bad.
#             # We don't want PSGet but maybe PowerShellget instead.
#             # Maybe install from nupkg directly from a nuget feed (Odata), doing the nupkg unzip ourselves?
#             # and we need PowerShellGet, v2 or v3
#             $webClient = New-Object -TypeName System.Net.WebClient

#             if ($env:HTTP_PROXY){
#                 if ($env:NO_PROXY){
#                     Write-Host "Creating WebProxy with 'HTTP_PROXY' and 'NO_PROXY' environment variables.
#                     $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList $env:HTTP_PROXY, $true, $env:NO_PROXY
#                 }
#                 else {
#                     Write-Host "Creating WebProxy with 'HTTP_PROXY' environment variable.
#                     $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList $env:HTTP_PROXY
#                 }

#                 $webClient.Proxy = $webproxy
#             }

#             Invoke-Expression -Command $webClient.DownloadString('http://bit.ly/GetPsGet') # this resolves to https://raw.githubusercontent.com/chaliy/psget/master/GetPsGet.ps1
#             # then in turns installs https://github.com/psget/psget/raw/master/PsGet/PsGet.psm1
#             # we should get rid of this relic
#         }

#         try {
#           # We should change the below to PowerShellGet (I assume)
#             # If the module isn't already loaded, ensure we can import it.
#             if (-not (Get-Module -Name PsGet -ErrorAction SilentlyContinue)) {
#                 Import-Module -Name PsGet -Force -ErrorAction Stop
#             }

#             Install-Module -Name Pester -Force
#         }
#         catch {
#             Write-Host "Installing from Github"

#             $zipFile = Join-Path (Get-Item -Path $VerifierDownloadPath).FullName -ChildPath "pester.zip"

#             if (-not (Test-Path $zipfile)) {
#                 $source = 'https://github.com/pester/Pester/archive/4.10.1.zip'
#                 $webClient = New-Object -TypeName Net.WebClient

#                 if ($env:HTTP_PROXY) {
#                     if ($env:NO_PROXY) {
#                         Write-Host "Creating WebProxy with 'HTTP_PROXY' and 'NO_PROXY' environment variables."
#                         $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList $env:HTTP_PROXY, $true, $env:NO_PROXY
#                     }
#                     else {
#                         Write-Host "Creating WebProxy with 'HTTP_PROXY' environment variable."
#                         $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList $env:HTTP_PROXY
#                     }

#                     $webClient.Proxy = $webproxy
#                 }

#                 [IO.File]::WriteAllBytes($zipfile, $webClient.DownloadData($source))

#                 [GC]::Collect()
#                 Write-Host "Downloaded Pester.zip"
#             }

#             # Try Expand-Archive first, only fall back to COM... (PS < 5.1)
#             Write-Host "Creating Shell.Application COM object"
#             $shellcom = New-Object -ComObject Shell.Application

#             Write-Host "Creating COM object for zip file."
#             $zipcomobject = $shellcom.Namespace($zipfile)

#             Write-Host "Creating COM object for module destination."
#             $destination = $shellcom.Namespace($VerifierModulePath)

#             Write-Host "Unpacking zip file."
#             $destination.CopyHere($zipcomobject.Items(), 0x610)

#             Rename-Item -Path (Join-Path $VerifierModulePath -ChildPath "Pester-4.10.1") -NewName 'Pester' -Force
#         }
#     }
# }

# if (-not (Test-Module Pester)) {
#     throw "Unable to install Pester.  Please include Pester in your base image or install during your converge."
# }


function ConvertFrom-PesterOutputObject {
    param (
        [parameter(ValueFromPipeline=$true)]
        [object]
        $InputObject
    )
    begin {
        $PesterModule = Import-Module Pester -Passthru
    }
    process {
        $DescribeGroup = $InputObject.testresult | Group-Object Describe
        foreach ($DescribeBlock in $DescribeGroup) {
            $PesterModule.Invoke({Write-Screen $args[0]}, "Describing $($DescribeBlock.Name)")
            $ContextGroup = $DescribeBlock.group | Group-Object Context
            foreach ($ContextBlock in $ContextGroup) {
                $PesterModule.Invoke({Write-Screen $args[0]}, "`tContext $($subheader.name)")
                foreach ($TestResult in $ContextBlock.group) {
                    $PesterModule.Invoke({Write-PesterResult $args[0]}, $TestResult)
                }
            }
        }

        $PesterModule.Invoke({Write-PesterReport $args[0]}, $InputObject)
    }
}
