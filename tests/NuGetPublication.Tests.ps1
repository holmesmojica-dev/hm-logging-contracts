[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\scripts\NuGetPublication.psm1') -Force

function Assert-Equal {
    param($Expected, $Actual)
    if ($Expected -ne $Actual) { throw "Expected '$Expected', received '$Actual'." }
}

function Assert-Throws {
    param([scriptblock]$Action)
    try { & $Action } catch { return }
    throw 'Expected an exception.'
}

Assert-Equal 'HDev.Hm.Logging.Contracts.1.0.0-preview.1.nupkg' (Get-HmNuGetPackageName -ReleaseVersion '1.0.0-preview.1')
Assert-Equal 'already_verified' (Resolve-HmNuGetVerificationDecision -PackageExists $true -IdentityMatches $true)
Assert-Equal 'publish' (Resolve-HmNuGetVerificationDecision -PackageExists $false -IdentityMatches $false)
Assert-Throws { Resolve-HmNuGetVerificationDecision -PackageExists $true -IdentityMatches $false }
Assert-Equal $true (Test-HmNuGetPublicationRequired -Decision 'publish')
Assert-Equal $false (Test-HmNuGetPublicationRequired -Decision 'already_verified')
Assert-Equal $true (Test-HmNuGetNotFoundStatusCode -StatusCode 404)
Assert-Equal $false (Test-HmNuGetNotFoundStatusCode -StatusCode 500)
Assert-Equal $false (Test-HmNuGetNotFoundStatusCode -StatusCode $null)
Write-Output 'NuGet publication tests passed.'
