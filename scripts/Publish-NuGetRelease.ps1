[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][string]$ReleaseVersion,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$GitHubOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:NUGET_API_KEY)) { throw 'NUGET_API_KEY must be supplied for NuGet publication.' }
& (Join-Path $PSScriptRoot 'Validate-ReleaseArtifact.ps1') -PackageDirectory $PackageDirectory -ReleaseVersion $ReleaseVersion -Commit $Commit
$packageName = "HDev.Hm.Logging.Contracts.$ReleaseVersion.nupkg"
$candidates = @(Get-ChildItem -LiteralPath $PackageDirectory -Filter "HDev.Hm.Logging.Contracts.$ReleaseVersion*.nupkg")
if ($candidates.Count -ne 1 -or $candidates[0].Name -cne $packageName) {
    throw "Expected exactly one release package named '$packageName'."
}

& dotnet nuget push $candidates[0].FullName --api-key $env:NUGET_API_KEY --source 'https://api.nuget.org/v3/index.json'
if ($LASTEXITCODE -ne 0) { throw "NuGet publication failed for '$packageName'." }

# Point 6 will verify an existing remote package before it may emit already_verified.
@("release_version=$ReleaseVersion", "source_commit=$Commit", 'nuget_state=published') | Add-Content -LiteralPath $GitHubOutputPath
