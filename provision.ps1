[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Install-PackageProvider Nuget -Force
Set-Content -Path "$env:Temp\test.txt" -Value 'testing'
