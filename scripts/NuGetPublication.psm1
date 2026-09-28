Set-StrictMode -Version Latest

function Get-HmNuGetPackageName {
    param([Parameter(Mandatory)][string]$ReleaseVersion)
    return "HDev.Hm.Logging.Contracts.$ReleaseVersion.nupkg"
}

function Get-HmNuGetPackageUri {
    param([Parameter(Mandatory)][string]$ReleaseVersion)
    $packageName = (Get-HmNuGetPackageName -ReleaseVersion $ReleaseVersion).ToLowerInvariant()
    return "https://api.nuget.org/v3-flatcontainer/hdev.hm.logging.contracts/$($ReleaseVersion.ToLowerInvariant())/$packageName"
}

function Assert-HmNuGetContentIdentity {
    param(
        [Parameter(Mandatory)][string]$LocalPackagePath,
        [Parameter(Mandatory)][string]$RemotePackagePath
    )

    # Builds only private Delivery tooling, never the Contracts package.
    $tool = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools/Hm.Logging.Contracts.ReleaseTools/Hm.Logging.Contracts.ReleaseTools.csproj'
    & dotnet run --project $tool --configuration Release --no-launch-profile -- assert-content-identity $LocalPackagePath $RemotePackagePath
    if ($LASTEXITCODE -ne 0) { throw 'NuGet content identity verification failed.' }
}

function Resolve-HmNuGetVerificationDecision {
    param(
        [Parameter(Mandatory)][bool]$PackageExists,
        [Parameter(Mandatory)][bool]$IdentityMatches,
        [Parameter(Mandatory)][bool]$ContentMatches
    )

    if (-not $PackageExists) { return 'publish' }
    if ($IdentityMatches -and $ContentMatches) { return 'already_verified' }
    throw 'The existing NuGet package has a conflicting release identity.'
}

function Test-HmNuGetPublicationRequired {
    param([Parameter(Mandatory)][string]$Decision)

    return $Decision -ceq 'publish'
}

function Test-HmNuGetNotFoundStatusCode {
    param([object]$StatusCode)
    return $null -ne $StatusCode -and [int]$StatusCode -eq 404
}

Export-ModuleMember -Function Assert-HmNuGetContentIdentity, Get-HmNuGetPackageName, Get-HmNuGetPackageUri, Resolve-HmNuGetVerificationDecision, Test-HmNuGetNotFoundStatusCode, Test-HmNuGetPublicationRequired
