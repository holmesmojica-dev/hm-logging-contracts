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
$candidates = @(Get-ChildItem -LiteralPath $PackageDirectory -Filter "HDev.Hm.Logging.Contracts.$ReleaseVersion*.nupkg")
if ($candidates.Count -ne 1 -or $candidates[0].Name -cne $packageName) {
    throw "Expected exactly one release package named '$packageName'."
}

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "hm-nuget-release-$([Guid]::NewGuid())"
$remotePackage = Join-Path $temporaryDirectory $packageName
$packageUri = Get-HmNuGetPackageUri -ReleaseVersion $ReleaseVersion
try {
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    $exists = $false
    try {
        Invoke-WebRequest -Uri $packageUri -OutFile $remotePackage -TimeoutSec 30
        $exists = $true
    }
    catch {
        $statusCode = if ($null -ne $_.Exception.Response) { $_.Exception.Response.StatusCode } else { $null }
        if (-not (Test-HmNuGetNotFoundStatusCode -StatusCode $statusCode)) { throw }
    }

    if ($exists) {
        try {
            & (Join-Path $PSScriptRoot 'Validate-ReleaseArtifact.ps1') -PackageDirectory $temporaryDirectory -ReleaseVersion $ReleaseVersion -Commit $Commit -SkipSymbolPackage
            $identityMatches = $true
        }
        catch { $identityMatches = $false }
        $decision = Resolve-HmNuGetVerificationDecision -PackageExists $true -IdentityMatches $identityMatches
        @("release_version=$ReleaseVersion", "source_commit=$Commit", "nuget_state=$decision") | Add-Content -LiteralPath $GitHubOutputPath
        return
    }

    Resolve-HmNuGetVerificationDecision -PackageExists $false -IdentityMatches $false | Out-Null
    if ([string]::IsNullOrWhiteSpace($env:NUGET_TRUSTED_PUBLISHING_API_KEY)) { throw 'NUGET_TRUSTED_PUBLISHING_API_KEY must be supplied for NuGet publication.' }
    & dotnet nuget push $candidates[0].FullName --api-key $env:NUGET_TRUSTED_PUBLISHING_API_KEY --source 'https://api.nuget.org/v3/index.json'
    if ($LASTEXITCODE -ne 0) { throw "NuGet publication failed for '$packageName'." }

    for ($attempt = 1; $attempt -le 60; $attempt++) {
        $available = $false
        try {
            Invoke-WebRequest -Uri $packageUri -OutFile $remotePackage -TimeoutSec 30
            $available = $true
        }
        catch {
            $statusCode = if ($null -ne $_.Exception.Response) { $_.Exception.Response.StatusCode } else { $null }
            if (-not (Test-HmNuGetNotFoundStatusCode -StatusCode $statusCode)) { throw }
            if ($attempt -eq 60) { throw 'NuGet did not make the published package available for identity verification within 15 minutes.' }
            Start-Sleep -Seconds 15
        }
        if ($available) {
            & (Join-Path $PSScriptRoot 'Validate-ReleaseArtifact.ps1') -PackageDirectory $temporaryDirectory -ReleaseVersion $ReleaseVersion -Commit $Commit -SkipSymbolPackage
            @("release_version=$ReleaseVersion", "source_commit=$Commit", 'nuget_state=published') | Add-Content -LiteralPath $GitHubOutputPath
            return
        }
    }
}
finally {
    if (Test-Path $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
}
