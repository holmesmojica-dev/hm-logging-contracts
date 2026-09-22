[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

$repositoryRoot = (& git rev-parse --show-toplevel).Trim()
$workflow = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/workflows/release.yml') -Raw
$buildScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Build-ReleaseArtifact.ps1') -Raw
$publishScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Publish-NuGetRelease.ps1') -Raw
$validationScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/validate.ps1') -Raw

Assert-True ($workflow -match '(?ms)^  build-artifact:.*?Build and validate release package.*?Upload immutable release artifact') 'The release workflow must build and validate the release artifact before uploading it.'
Assert-True ($buildScript -match 'Validate-ReleaseArtifact\.ps1') 'Release artifact production must validate its package before transport.'
Assert-True ($workflow -match '(?ms)^  attest-artifacts:.*?needs: \[preflight, build-artifact\].*?Verify validated artifact integrity') 'Attestation must depend on the validated build artifact and verify its integrity.'
Assert-True ($workflow -match '(?ms)^  attest-artifacts:.*?permissions:\s+contents: read\s+id-token: write\s+attestations: write\s+artifact-metadata: write') 'The attestation job must have only the permissions required for provenance.'
Assert-True (($workflow | Select-String -Pattern 'uses: actions/attest@' -AllMatches).Matches.Count -eq 2) 'Both release packages must be attested.'
Assert-True ($workflow -match 'HDev\.Hm\.Logging\.Contracts\.\$\{\{ needs\.preflight\.outputs\.release_version \}\}\.nupkg') 'The NuGet package must be within the attestation boundary.'
Assert-True ($workflow -match 'HDev\.Hm\.Logging\.Contracts\.\$\{\{ needs\.preflight\.outputs\.release_version \}\}\.snupkg') 'The NuGet symbol package must be within the attestation boundary.'
Assert-True ($workflow -match '(?ms)^  publish-nuget:.*?needs: \[preflight, build-artifact, attest-artifacts\]') 'NuGet publication must depend on successful attestation.'
Assert-True ($workflow -match 'gh attestation verify') 'The workflow must verify generated attestations before publication.'
Assert-True ($workflow -notmatch 'secrets\.NUGET_API_KEY') 'The official release workflow must not use a long-lived NuGet API key.'
Assert-True ($workflow -match 'NuGet/login@d22cc5f58ff5b88bf9bd452535b4335137e24544') 'NuGet publication must use the immutable trusted-publishing login action.'
Assert-True ($workflow -match '(?ms)^  publish-nuget:.*?permissions:\s+contents: read\s+id-token: write') 'NuGet publication must request its OIDC token with least privilege.'
Assert-True ($publishScript -match 'Assert-ReleaseArtifactManifest') 'NuGet publication must verify the release artifact integrity manifest.'
Assert-True ($publishScript -match 'Validate-ReleaseArtifact\.ps1') 'NuGet publication must validate its package before publication.'
Assert-True ($publishScript -notmatch '\$env:NUGET_API_KEY') 'NuGet publication must not read a long-lived API key.'
Assert-True (($buildScript | Select-String -Pattern 'dotnet pack' -AllMatches).Matches.Count -eq 1) 'The release build must pack exactly once.'
Assert-True ($publishScript -notmatch 'dotnet pack') 'NuGet publication must not rebuild the release artifact.'
Assert-True ($validationScript -notmatch 'Publish-NuGetRelease|NUGET_TRUSTED_PUBLISHING_API_KEY|NuGet/login') 'Local validation must not publish or request release credentials.'

Write-Output 'Release workflow tests passed.'
