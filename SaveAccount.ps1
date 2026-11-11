#requires -Version 5.1
$ErrorActionPreference='Stop'
$setup=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CampusNetworkAutoLogin\CredentialSetup.ps1'
if(-not(Test-Path -LiteralPath $setup)){throw 'Run 1-Prepare.cmd first.'}
& $setup
