[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Commit,

    [Parameter()]
    [string]$RepositoryPath = (& git rev-parse --show-toplevel).Trim()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ReleaseVersioning.psm1') -Force

Assert-HmCheckedOutCommit -RepositoryPath $RepositoryPath -Commit $Commit

& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'validate.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "Release commit '$Commit' did not pass repository validation."
}
