[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

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

    if ($env:HTTP_PROXY){
        if ($env:NO_PROXY){
            Write-Host "Creating WebProxy with 'HTTP_PROXY' and 'NO_PROXY' environment variables."
            $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList $env:HTTP_PROXY, $true, $env:NO_PROXY
        }
        else {
            Write-Host "Creating WebProxy with 'HTTP_PROXY' environment variable."
            $webproxy = New-Object -TypeName System.Net.WebProxy -ArgumentList $env:HTTP_PROXY
        }

        $wc.Proxy = $webproxy
    }

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

    [GC]::Collect()
}

function Set-PSRepo {
    param(
        [Parameter(Mandatory)]
        $Repository
    )
    if (-not (Get-Command Get-PSRepository) -and (Get-Command Get-PackageSource)) {
        # Old version of PSGet do not have a *-PSrepository but have *-PackageSource instead.
        if (Get-PackageSource -Name $Repository.Name)  {
            Set-PackageSource @Repository
        }
        else {
            Register-PackageSource @Repository
        }
    }
    elseif (Get-Command Get-PSRepository) {
        if (Get-PSRepository -Name $Repository.Name -ErrorAction SilentlyContinue) {
            # The repo exists, we should use Set-PSRepository and splat parameters
            Set-PSRepository @Repository
        }
        else {
            # The repo does not exist, use Register-PSRepository and splat
            Register-PSRepository @Repository
        }
    }
    else {
        Write-Host "Cannot Set PS Repository, command Set or Register for PSRepository or PackageSource not found."
    }
}

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
