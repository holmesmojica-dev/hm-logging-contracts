[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Tag,

    [Parameter()]
    [string]$RepositoryPath = (& git rev-parse --show-toplevel).Trim(),

    [Parameter()]
    [string]$MainBranch = 'main',

    [Parameter()]
    [string]$GitHubOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ReleaseVersioning.psm1') -Force

$release = Resolve-HmReleaseContext -RepositoryPath $RepositoryPath -Tag $Tag -MainBranch $MainBranch

if (-not [string]::IsNullOrWhiteSpace($GitHubOutputPath)) {
    @(
        "release_version=$($release.ReleaseVersion)"
        "tag_commit=$($release.Commit)"
        "release_tag=$($release.Tag)"
    ) | Add-Content -LiteralPath $GitHubOutputPath
}

$release | ConvertTo-Json -Compress
