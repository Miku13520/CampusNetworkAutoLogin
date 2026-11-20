#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CampusTasks.ps1')

$tasks = @(Get-CampusTasks -RequireAll)
if (-not (Test-Path -LiteralPath (Join-Path $campusInstallDirectory 'credential.xml'))) {
    throw 'Run 2-SaveAccount.cmd and save your account first.'
}
& $campusScriptPath -ResetAuthHold
if ($LASTEXITCODE -ne 0) { throw 'Could not reset authentication state. See campus-login.log.' }

$enabled = @()
try {
    foreach ($task in $tasks) {
        if ($task.Settings.Enabled) { continue }
        Enable-ScheduledTask -InputObject $task | Out-Null
        $enabled += $task
    }
} catch {
    Disable-CampusTasks $enabled
    throw
}
Start-ScheduledTask -InputObject $tasks[0]
Write-Host 'Logon and two-minute checks enabled. A network check has started.'
Write-Host (Join-Path $campusInstallDirectory 'campus-login.log')
