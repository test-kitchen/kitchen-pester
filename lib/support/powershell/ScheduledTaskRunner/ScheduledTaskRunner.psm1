import-module NamedPipes -force

$script:TaskLastExitCode = @{}

function Add-ScheduledTaskCommand {
  param ([string]$Name, [scriptblock]$Action)
  $command = @"
  `$env:temp = '$env:temp';
  `$env:psmodulepath = '$env:psmodulepath';
  import-module NamedPipes -force;

  # Set up named pipe
  start-sleep -seconds 5

  New-NamedPipe -Role Client -Direction Out -Quiet -Name 'kitchen-$name';
  Connect-NamedPipeClient -Name 'kitchen-$name';

  # Run the real action and send it down the named pipe
  try {
     `$ActionString = @'
$($action.ToString())
'@

     [scriptblock]::create(`$ActionString).InvokeReturnAsIs() |
      write-NamedPipe -Name 'kitchen-$name'
  }
  catch [Exception] {
    write-NamedPipe -name 'kitchen-$name' -content `$_.exception.message
    Write-NamedPipe -Name 'kitchen-$name' -content `$_.exception.stacktrace
  }
  finally {
    # Close out named pipe
    Send-StopReadingCommand -Name 'kitchen-$name';
    Remove-NamedPipe -Name 'kitchen-$name';
  }
"@

  try {
    $ActionWithEnvironment = [scriptblock]::Create($command)
  }
  catch {
    Write-Output "Failed to validate: "
    Write-Output $command
    throw $_.exception
  }

  $ActionWithEnvironment.ToString() | Out-file "$env:temp/$Name.ps1"
  if (test-path "$env:temp/$name.ps1") {
    schtasks /create /tn "kitchen-$name" /ru System /sc daily /st 00:00 /rl HIGHEST /f /tr "powershell -noprofile -executionpolicy unrestricted -file $env:temp/$name.ps1" | Out-Null
    Write-Host "`tCreated Scheduled Task $Name."
  }
  else {
    throw "failed to create scheduled task command."
  }
}

function Remove-ScheduledTaskCommand {
  param ([string]$Name)
  schtasks /delete /tn "kitchen-$name" /f | Out-Null
  Write-Host "`tDeleted Scheduld Task $Name."
}

function Get-ScheduledTaskExitCode {
  param ([string]$Name)
  (Get-ScheduledTaskStatus -name $name).'Last Result' |
    where {-not [string]::IsNullOrEmpty($_)} |
    foreach {[int]::Parse($_.trim())}
}

function Get-ScheduledTaskStatus {
  param ([string]$Name)
  $task = schtasks /query /tn "kitchen-$name" /fo csv /v |
    ConvertFrom-Csv
  $task
}

function Invoke-ScheduledTaskCommand {
  param ([string]$Name)
  try {
    new-namedpipe -Role Server -Direction In -Quiet -Name "kitchen-$name"
    schtasks /run /tn "kitchen-$name" | Out-Null
    Write-Host "`tRunning Scheduled Task $Name."
    Start-NamedPipeServer -Name "kitchen-$name"
    Read-NamedPipe -Name "kitchen-$name"
  }
  finally {
    Remove-NamedPipe -name "kitchen-$name"
    while ((Get-ScheduledTaskStatus -name $name).Status -notlike 'Ready') {
      start-sleep -seconds 1
    }
  }
}