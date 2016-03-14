Add-Type -AssemblyName System.Core;

$script:NamedPipes = @()

function New-NamedPipe {
  param (
    [parameter(Mandatory=$true)]
    [ValidateSet('In', 'Out')]
    [string]
    $Direction,
    [parameter(Mandatory=$true)]
    [ValidateSet('Client', 'Server')]
    [string]
    $Role,
    [parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Name, 
    [switch]
    $Quiet
  )
  try {
    $pipeReader = $null
    $pipeWriter = $null

    if ($Role -like 'Server') {
      $pipe = new-object -ErrorAction Stop System.IO.Pipes.NamedPipeServerStream($Name,
        [System.IO.Pipes.PipeDirection]::$Direction)
    }
    else {
      $pipe = new-object -ErrorAction Stop System.IO.Pipes.NamedPipeClientStream($env:ComputerName,
        $Name, [System.IO.Pipes.PipeDirection]::$Direction)
    }
    if ($Direction -like 'In') {
      $pipeReader = new-object System.IO.StreamReader($pipe)
    }
    else {
      $pipeWriter = new-object System.IO.StreamWriter($pipe)
    }
    $output = new-object PSObject -property @{
      Name = $Name
      NamedPipe = $pipe
      Role = $Role
      Direction = $Direction
      PipeReader = $pipeReader
      PipeWriter = $pipeWriter
    }
    $script:NamedPipes += $output
    if (-not $Quiet) {$output}
  }
  catch {
    throw "Failed to create the named pipe."
  }
}

function Get-NamedPipe {
  param (
    $Name = '*',
    $Role = '*'
  )
  $pipe = $null
  $pipe = $script:NamedPipes |
    where {$_.name -like $Name -and $_.role -like $Role} 
  if ($pipe -eq $null) { throw "Unable to find pipe $Name" }
  return $pipe
}

function Start-NamedPipeServer {
  param ($Name)
  $PipeServer = Get-NamedPipe -Name $Name -Role Server
  $PipeServer.NamedPipe.WaitForConnection()
  Write-Host "Named Pipe $Name is connected."
}

function Connect-NamedPipeClient {
  param ($Name)
  $PipeClient = Get-NamedPipe -Name $Name -Role Client
  $PipeClient.NamedPipe.Connect()
  if ($PipeClient.PipeWriter -ne $null) {
    $PipeClient.pipeWriter.AutoFlush = $true
  }
}

function Write-NamedPipe {
  param(
    [parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Name,
    [parameter(ValueFromPipeline=$true)]
    [string]
    $Content)
  begin {
    $Pipe = Get-NamedPipe -Name $Name |
      where {$_.PipeWriter -ne $null}
  }
  process {
    if ($Pipe.NamedPipe.IsConnected){
      $Pipe.PipeWriter.Writeline($Content)
    }
  }
}

function Read-NamedPipe {
  param ($Name)
  $Pipe = Get-NamedPipe -Name $Name | where {$_.PipeReader -ne $null}
  while ($Pipe.NamedPipe.IsConnected) {
    $output = $Pipe.PipeReader.ReadLine()
    if ($output -like "STOP READING $Name") {
      break;
    }
    $output
  }
}

function Send-StopReadingCommand {
  param ($Name)
  Write-NamedPipe -Name $Name -Content "STOP READING $Name"
}

function Remove-NamedPipe {
  param ($name)
  Get-NamedPipe -Name $Name |
    foreach {
      if ($_.Pipewriter -ne $null) {
        $_.PipeWriter.dispose()
      }
      if ($_.Pipereader -ne $null) {
        $_.Pipereader.dispose()
      }
      $_.NamedPipe.dispose()
    }
  $script:NamedPipes = $script:NamedPipes | where {$_.name -notlike $Name}
}
