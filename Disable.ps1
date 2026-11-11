#requires -Version 5.1
$ErrorActionPreference='Stop'
$task=Get-ScheduledTask -TaskName 'CampusNetworkAutoLogin' -ErrorAction Stop
if(($task.Actions.Arguments -join ' ') -notlike '*CampusNetworkAutoLogin\CampusLogin.ps1*'){throw 'Unexpected task action.'}
Disable-ScheduledTask -TaskName 'CampusNetworkAutoLogin' | Out-Null
if($task.State -eq 'Running'){Stop-ScheduledTask -TaskName 'CampusNetworkAutoLogin'}
Write-Host 'Disabled. Current campus connection is unchanged.'
