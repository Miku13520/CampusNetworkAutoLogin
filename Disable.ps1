#requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'CampusTasks.ps1')

$tasks = @(Get-CampusTasks)
Disable-CampusTasks $tasks
Write-Host 'Campus login checks disabled.'
