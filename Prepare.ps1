#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CampusTasks.ps1')

$existing = @(Get-CampusTasks)
$user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$arguments = '-NoProfile -NonInteractive -WindowStyle Hidden ' + $campusScriptArgument
$logonAction = New-ScheduledTaskAction -Execute $campusPowerShell -Argument $arguments -WorkingDirectory $campusInstallDirectory
$periodicAction = New-ScheduledTaskAction -Execute $campusPowerShell -Argument ($arguments + ' -Periodic') -WorkingDirectory $campusInstallDirectory
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$logonTrigger.Delay = 'PT15S'
$interval = New-TimeSpan -Minutes 2
$periodicTrigger = New-ScheduledTaskTrigger -Once -At ((Get-Date) + $interval) -RepetitionInterval $interval
$periodicTrigger.Repetition.StopAtDurationEnd = $false
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 3) -StartWhenAvailable -MultipleInstances IgnoreNew
$settings.Enabled = $false
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$definitions = @(
    New-ScheduledTask -Action $logonAction -Trigger $logonTrigger -Settings $settings -Principal $principal -Description 'Check campus authentication after Windows logon.'
    New-ScheduledTask -Action $periodicAction -Trigger $periodicTrigger -Settings $settings -Principal $principal -Description 'Check campus authentication every two minutes while signed in.'
)

Disable-CampusTasks $existing
[void][IO.Directory]::CreateDirectory($campusInstallDirectory)
foreach ($name in @('CampusLogin.ps1', 'CredentialSetup.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $campusInstallDirectory -Force
}
if (-not (Test-Path -LiteralPath (Join-Path $campusInstallDirectory 'config.json'))) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config.json') -Destination $campusInstallDirectory
}
for ($index = 0; $index -lt $campusTaskNames.Count; $index++) {
    Register-ScheduledTask -TaskPath $campusTaskPath -TaskName $campusTaskNames[$index] -InputObject $definitions[$index] -Force | Out-Null
}

Write-Host 'Step 1 complete. Both tasks are disabled.'
if (Test-Path -LiteralPath (Join-Path $campusInstallDirectory 'credential.xml')) {
    Write-Host 'Existing account retained. Next, run 3-Enable.cmd.'
} else {
    Write-Host 'Next, run 2-SaveAccount.cmd, then 3-Enable.cmd.'
}
