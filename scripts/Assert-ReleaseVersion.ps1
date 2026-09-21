[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReleaseVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ReleaseVersioning.psm1') -Force

Assert-HmReleaseVersion -ReleaseVersion $ReleaseVersion | Out-Null
