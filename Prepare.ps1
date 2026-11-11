#requires -Version 5.1
$ErrorActionPreference='Stop'
$taskName='CampusNetworkAutoLogin'
$sourceDirectory=Split-Path -Parent $MyInvocation.MyCommand.Path
$base=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CampusNetworkAutoLogin'
[void][IO.Directory]::CreateDirectory($base)
$existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($existing -and ($existing.Actions.Arguments -join ' ') -notlike '*CampusNetworkAutoLogin\CampusLogin.ps1*'){throw 'A different task already uses this name.'}
if($existing){Disable-ScheduledTask -TaskName $taskName | Out-Null}
foreach($name in @('CampusLogin.ps1','config.json','CredentialSetup.ps1')){
    Copy-Item -LiteralPath (Join-Path $sourceDirectory $name) -Destination (Join-Path $base $name) -Force
}
$psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$who=[Security.Principal.WindowsIdentity]::GetCurrent().Name
$action=New-ScheduledTaskAction -Execute $psExe -Argument ('-NoProfile -NonInteractive -WindowStyle Minimized -File "'+(Join-Path $base 'CampusLogin.ps1')+'"') -WorkingDirectory $base
$trigger=New-ScheduledTaskTrigger -AtLogOn -User $who
$trigger.Delay='PT15S'
$settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 3) -StartWhenAvailable -MultipleInstances IgnoreNew
$principal=New-ScheduledTaskPrincipal -UserId $who -LogonType Interactive -RunLevel Limited
$task=New-ScheduledTask -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Authenticate once on Fzdxkjy-web after user logon; exit if already online.'
$task.Settings.Enabled=$false
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
Write-Host 'Step 1 complete. Task is DISABLED. Next: run 2-SaveAccount.cmd.'
