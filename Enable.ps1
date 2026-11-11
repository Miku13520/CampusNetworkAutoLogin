#requires -Version 5.1
$ErrorActionPreference='Stop'
$base=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CampusNetworkAutoLogin'
if(-not(Test-Path -LiteralPath (Join-Path $base 'credential.xml'))){throw 'Run 2-SaveAccount.cmd and save your account first.'}
$task=Get-ScheduledTask -TaskName 'CampusNetworkAutoLogin' -ErrorAction Stop
if(($task.Actions.Arguments -join ' ') -notlike '*CampusNetworkAutoLogin\CampusLogin.ps1*'){throw 'Unexpected task action.'}
Enable-ScheduledTask -TaskName 'CampusNetworkAutoLogin' | Out-Null
Start-ScheduledTask -TaskName 'CampusNetworkAutoLogin'
Write-Host 'Enabled. Network check started. Log: '
Write-Host (Join-Path $base 'campus-login.log')
Write-Host 'A check while already online does not prove a new login. Verify after your next normal reboot.'
