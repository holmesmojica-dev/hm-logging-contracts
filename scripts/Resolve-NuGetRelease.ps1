[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][string]$ReleaseVersion,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$GitHubOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'NuGetPublication.psm1') -Force

& (Join-Path $PSScriptRoot 'Validate-ReleaseArtifact.ps1') -PackageDirectory $PackageDirectory -ReleaseVersion $ReleaseVersion -Commit $Commit
& (Join-Path $PSScriptRoot 'Assert-ReleaseArtifactManifest.ps1') -PackageDirectory $PackageDirectory -ReleaseVersion $ReleaseVersion

$packageName = Get-HmNuGetPackageName -ReleaseVersion $ReleaseVersion
$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "hm-nuget-resolution-$([Guid]::NewGuid())"
$remotePackage = Join-Path $temporaryDirectory $packageName
$packageUri = Get-HmNuGetPackageUri -ReleaseVersion $ReleaseVersion
try {
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    $packageExists = $false
    try {
        Invoke-WebRequest -Uri $packageUri -OutFile $remotePackage -TimeoutSec 30
        $packageExists = $true
    }
    catch {
        $statusCode = if ($null -ne $_.Exception.Response) { $_.Exception.Response.StatusCode } else { $null }
        if (-not (Test-HmNuGetNotFoundStatusCode -StatusCode $statusCode)) { throw }
    }

    $identityMatches = $false
    if ($packageExists) {
        try {
            & (Join-Path $PSScriptRoot 'Validate-ReleaseArtifact.ps1') -PackageDirectory $temporaryDirectory -ReleaseVersion $ReleaseVersion -Commit $Commit -SkipSymbolPackage
            $identityMatches = $true
        }
        catch { $identityMatches = $false }
    }

    $decision = Resolve-HmNuGetVerificationDecision -PackageExists $packageExists -IdentityMatches $identityMatches
    @("release_version=$ReleaseVersion", "source_commit=$Commit", "nuget_state=$decision") | Add-Content -LiteralPath $GitHubOutputPath
}
finally {
    if (Test-Path -LiteralPath $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
}
