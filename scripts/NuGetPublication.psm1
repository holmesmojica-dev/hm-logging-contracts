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

function Resolve-HmNuGetVerificationDecision {
    param(
        [Parameter(Mandatory)][bool]$PackageExists,
        [Parameter(Mandatory)][bool]$IdentityMatches
    )

    if (-not $PackageExists) { return 'publish' }
    if ($IdentityMatches) { return 'already_verified' }
    throw 'The existing NuGet package has a conflicting release identity.'
}

function Test-HmNuGetNotFoundStatusCode {
    param([object]$StatusCode)
    return $null -ne $StatusCode -and [int]$StatusCode -eq 404
}

Export-ModuleMember -Function Get-HmNuGetPackageName, Get-HmNuGetPackageUri, Resolve-HmNuGetVerificationDecision, Test-HmNuGetNotFoundStatusCode
