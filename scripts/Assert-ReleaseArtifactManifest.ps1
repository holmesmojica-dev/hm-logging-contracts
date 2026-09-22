[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][string]$ReleaseVersion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ReleaseArtifactIntegrity.psm1') -Force

Assert-HmReleaseArtifactManifest -PackageDirectory $PackageDirectory -ReleaseVersion $ReleaseVersion
