#requires -Version 5.1
$campusTaskNames = @('CampusNetworkAutoLogin', 'CampusNetworkAutoLogin-Periodic')
$campusTaskPath = '\'
$campusInstallDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CampusNetworkAutoLogin'
$campusScriptPath = Join-Path $campusInstallDirectory 'CampusLogin.ps1'
$campusScriptArgument = '-File "' + $campusScriptPath + '"'
$campusPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Get-CampusTasks {
    param([switch]$RequireAll)
    foreach ($name in $campusTaskNames) {
        $task = Get-ScheduledTask -TaskPath $campusTaskPath -TaskName $name -ErrorAction SilentlyContinue
        if ($null -eq $task) {
            if ($RequireAll) { throw "Task $name is missing. Run 1-Prepare.cmd first." }
            continue
        }
        $actions = @($task.Actions)
        if ($actions.Count -ne 1 -or $actions[0].Execute -ine $campusPowerShell -or
            ([string]$actions[0].Arguments).IndexOf($campusScriptArgument, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            throw "A different task already uses the name $name."
        }
        $task
    }
}

function Disable-CampusTasks {
    param([array]$Tasks)
    foreach ($task in $Tasks) {
        Disable-ScheduledTask -InputObject $task | Out-Null
    }
    foreach ($task in $Tasks) {
        Stop-ScheduledTask -InputObject $task
    }
}
