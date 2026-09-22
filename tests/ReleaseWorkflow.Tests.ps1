[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-ReleaseJobBlock {
    param([Parameter(Mandatory)][string]$Workflow, [Parameter(Mandatory)][string]$JobName)

    $match = [regex]::Match($Workflow, "(?ms)^  $([regex]::Escape($JobName)):\r?\n(.*?)(?=^  [a-z][a-z-]*:\r?\n|\z)")
    if (-not $match.Success) { throw "Release workflow job '$JobName' was not found." }
    return $match.Groups[1].Value
}

function Assert-CheckoutBeforeRepositoryScripts {
    param([Parameter(Mandatory)][string]$JobName, [Parameter(Mandatory)][string]$JobBlock)

    $firstScriptIndex = $JobBlock.IndexOf('./scripts/', [System.StringComparison]::Ordinal)
    if ($firstScriptIndex -lt 0) { return }

    $checkoutIndex = $JobBlock.IndexOf('uses: actions/checkout@', [System.StringComparison]::Ordinal)
    Assert-True ($checkoutIndex -ge 0 -and $checkoutIndex -lt $firstScriptIndex) "Release job '$JobName' must check out the repository before its first repository-local script."
}

$repositoryRoot = (& git rev-parse --show-toplevel).Trim()
$workflow = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/workflows/release.yml') -Raw
$buildScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Build-ReleaseArtifact.ps1') -Raw
$publishScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Publish-NuGetRelease.ps1') -Raw
$resolveNuGetScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Resolve-NuGetRelease.ps1') -Raw
$publishBsrScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Publish-BsrRelease.ps1') -Raw
$updateBsrBaselineScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Update-BsrBaseline.ps1') -Raw
$publishGitHubReleaseScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Publish-GitHubRelease.ps1') -Raw
$gitHubReleaseModule = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/GitHubRelease.psm1') -Raw
$validationScript = Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/validate.ps1') -Raw
$triggerBlock = [regex]::Match($workflow, '(?ms)^on:\s*\r?\n(.*?)(?=^permissions:)').Value
$releaseJobBlocks = @{}
foreach ($jobMatch in [regex]::Matches($workflow, '(?ms)^  ([a-z][a-z-]*):\r?\n(.*?)(?=^  [a-z][a-z-]*:\r?\n|\z)')) {
    $jobName = $jobMatch.Groups[1].Value
    $jobBlock = $jobMatch.Groups[2].Value
    if ($jobBlock.Contains('./scripts/', [System.StringComparison]::Ordinal)) {
        $releaseJobBlocks[$jobName] = $jobBlock
        Assert-CheckoutBeforeRepositoryScripts -JobName $jobName -JobBlock $jobBlock
    }
}

Assert-True ($triggerBlock -match '(?ms)^on:\s*\r?\n\s+push:\s*\r?\n\s+tags:\s*\r?\n\s+- ''v\*''') 'The official release workflow must trigger only for v-prefixed pushed tags.'
Assert-True ($triggerBlock -notmatch 'branches:|pull_request:|workflow_dispatch:|schedule:|repository_dispatch:') 'The official release workflow must not expose alternate publication triggers.'
Assert-True ($workflow -match '(?ms)^  preflight:.*?uses: actions/checkout@.*?fetch-depth: 0.*?Resolve release identity') 'Release preflight must fetch complete branch and tag history.'
Assert-True ($workflow -match '(?ms)Resolve release identity.*?Resolve-ReleaseVersion\.ps1.*?-Tag "\$env:GITHUB_REF_NAME".*?-MainBranch ''origin/main''') 'Tag-triggered release identity resolution must validate against the fetched origin/main reference.'
Assert-True ($workflow -match '(?ms)Validate deterministic BSR prerequisites.*?Validate-BsrRelease\.ps1.*?-Tag.*?steps\.release\.outputs\.release_tag.*?-LastBsrCommitId.*?LAST_BSR_COMMIT_ID.*?-MainBranch ''origin/main''') 'Tag-triggered BSR preflight must validate against the fetched origin/main reference.'
Assert-True ($releaseJobBlocks['attest-artifacts'] -match '(?ms)uses: actions/checkout@.*?ref: \$\{\{ needs\.preflight\.outputs\.source_commit \}\}.*?Download validated release artifact.*?Verify validated artifact integrity') 'Attestation must check out the immutable source before downloading and verifying the artifact.'
Assert-True ($releaseJobBlocks['publish-nuget'] -match '(?ms)uses: actions/checkout@.*?ref: \$\{\{ needs\.preflight\.outputs\.source_commit \}\}.*?Download validated release artifact.*?Verify validated artifact integrity.*?Resolve NuGet release state') 'NuGet publication must check out the immutable source before artifact verification and resolution.'
Assert-True ($releaseJobBlocks['publish-bsr'] -match '(?ms)uses: actions/checkout@.*?ref: \$\{\{ needs\.preflight\.outputs\.source_commit \}\}.*?fetch-depth: 0.*?Publish BSR module') 'BSR publication must retain its full-history immutable-source checkout.'
Assert-True ($releaseJobBlocks['persist-bsr-state'] -match '(?ms)uses: actions/checkout@.*?ref: \$\{\{ needs\.publish-bsr\.outputs\.source_commit \}\}.*?Persist immutable BSR commit') 'Baseline persistence must check out the immutable BSR source before its repository-local script.'
Assert-True ($releaseJobBlocks['post-publication'] -match '(?ms)uses: actions/checkout@.*?ref: \$\{\{ needs\.preflight\.outputs\.source_commit \}\}.*?Create or verify GitHub Release') 'GitHub Release creation must check out the immutable source before its repository-local script.'
Assert-True ($workflow -match '(?ms)^  build-artifact:.*?Build and validate release package.*?Upload immutable release artifact') 'The release workflow must build and validate the release artifact before uploading it.'
Assert-True ($buildScript -match 'Validate-ReleaseArtifact\.ps1') 'Release artifact production must validate its package before transport.'
Assert-True ($workflow -match '(?ms)^  attest-artifacts:.*?needs: \[preflight, build-artifact\].*?Verify validated artifact integrity') 'Attestation must depend on the validated build artifact and verify its integrity.'
Assert-True ($workflow -match '(?ms)^  attest-artifacts:.*?permissions:\s+contents: read\s+id-token: write\s+attestations: write\s+artifact-metadata: write') 'The attestation job must have only the permissions required for provenance.'
Assert-True (($workflow | Select-String -Pattern 'uses: actions/attest@' -AllMatches).Matches.Count -eq 2) 'Both release packages must be attested.'
Assert-True ($workflow -match 'HDev\.Hm\.Logging\.Contracts\.\$\{\{ needs\.preflight\.outputs\.release_version \}\}\.nupkg') 'The NuGet package must be within the attestation boundary.'
Assert-True ($workflow -match 'HDev\.Hm\.Logging\.Contracts\.\$\{\{ needs\.preflight\.outputs\.release_version \}\}\.snupkg') 'The NuGet symbol package must be within the attestation boundary.'
Assert-True ($workflow -match '(?ms)^  publish-nuget:.*?needs: \[preflight, build-artifact, attest-artifacts\]') 'NuGet publication must depend on successful attestation.'
Assert-True ($workflow -match "(?ms)Resolve NuGet release state.*?id: resolve.*?Log in to NuGet.org with OIDC.*?if: steps\.resolve\.outputs\.nuget_state == 'publish'") 'NuGet login must occur only after a publish decision.'
Assert-True ($workflow -match "(?ms)Publish NuGet package.*?if: steps\.resolve\.outputs\.nuget_state == 'publish'") 'NuGet publication must occur only after a publish decision.'
Assert-True ($workflow -match 'gh attestation verify') 'The workflow must verify generated attestations before publication.'
Assert-True ($workflow -notmatch 'secrets\.NUGET_API_KEY') 'The official release workflow must not use a long-lived NuGet API key.'
Assert-True ($workflow -match 'NuGet/login@d22cc5f58ff5b88bf9bd452535b4335137e24544') 'NuGet publication must use the immutable trusted-publishing login action.'
Assert-True ($workflow -match '(?ms)^  publish-nuget:.*?permissions:\s+contents: read\s+id-token: write') 'NuGet publication must request its OIDC token with least privilege.'
Assert-True ($publishScript -match 'Assert-ReleaseArtifactManifest') 'NuGet publication must verify the release artifact integrity manifest.'
Assert-True ($publishScript -match 'Validate-ReleaseArtifact\.ps1') 'NuGet publication must validate its package before publication.'
Assert-True ($resolveNuGetScript -notmatch 'NUGET_TRUSTED_PUBLISHING_API_KEY') 'NuGet resolution must not require a Trusted Publishing credential.'
Assert-True ($publishScript -notmatch '\$env:NUGET_API_KEY') 'NuGet publication must not read a long-lived API key.'
Assert-True (($buildScript | Select-String -Pattern 'dotnet pack' -AllMatches).Matches.Count -eq 1) 'The release build must pack exactly once.'
Assert-True ($publishScript -notmatch 'dotnet pack') 'NuGet publication must not rebuild the release artifact.'
Assert-True ($publishBsrScript.IndexOf('Resolve-BsrReleaseCommit -Reference $reference') -lt $publishBsrScript.IndexOf('& $BufCommand push')) 'BSR must resolve an existing release before it can push.'
Assert-True ($publishBsrScript -match '\[string\]\$BufCommand = ''buf''') 'BSR publication must default to the Buf command.'
Assert-True ($workflow -notmatch 'Publish-BsrRelease\.ps1\s+-BufCommand') 'The production workflow must not override the default Buf command.'
Assert-True ($workflow -match "publish-bsr\.outputs\.bsr_state == 'published' \|\| needs\.publish-bsr\.outputs\.bsr_state == 'already_verified'") 'Baseline persistence must accept recovered BSR state.'
Assert-True ($workflow -match 'Update-BsrBaseline\.ps1 -CommitId "\$\{\{ needs\.publish-bsr\.outputs\.bsr_commit_id \}\}"') 'Baseline persistence must use the recovered immutable BSR commit ID.'
Assert-True ($updateBsrBaselineScript -match '\$CommitId -cnotmatch ''\^\[0-9a-f\]\{32\}\$''') 'Baseline persistence must reject INITIAL and malformed publication commit IDs.'
Assert-True ($workflow -match '(?ms)^  post-publication:.*?needs: \[preflight, build-artifact, attest-artifacts, publish-nuget, publish-bsr, persist-bsr-state\].*?permissions:\s+contents: write') 'GitHub Release creation must follow baseline persistence with contents-write scoped to its job.'
Assert-True ($workflow -match '(?ms)^  post-publication:.*?Publish-GitHubRelease\.ps1.*?-Tag.*?needs\.preflight\.outputs\.release_tag.*?-ReleaseVersion.*?needs\.preflight\.outputs\.release_version') 'GitHub Release creation must derive identity from the release tag and version outputs.'
Assert-True ($publishGitHubReleaseScript -match 'Resolve-HmReleaseTag') 'GitHub Release creation must validate the release tag identity.'
Assert-True ($publishGitHubReleaseScript -match "Contains\('-', \[System\.StringComparison\]::Ordinal\)") 'GitHub Release prerelease state must derive from the release version.'
Assert-True ($publishGitHubReleaseScript -match 'gh release view') 'GitHub Release creation must resolve an existing release before creating one.'
Assert-True ($publishGitHubReleaseScript -match '\$lookup\.State -eq ''existing''') 'An existing GitHub Release must satisfy a retry without recreation.'
Assert-True ($gitHubReleaseModule -match '--generate-notes') 'GitHub Release creation must use generated release notes.'
Assert-True ($gitHubReleaseModule -match '--verify-tag') 'GitHub Release creation must not create or move a release tag.'
Assert-True ($publishGitHubReleaseScript -notmatch 'gh release edit|gh release delete') 'GitHub Release retries must not modify or delete existing releases.'
Assert-True ($validationScript -notmatch 'Publish-NuGetRelease|NUGET_TRUSTED_PUBLISHING_API_KEY|NuGet/login') 'Local validation must not publish or request release credentials.'
Assert-True ($validationScript -notmatch 'Publish-GitHubRelease|gh release') 'Local validation must not create GitHub Releases.'

Write-Output 'Release workflow tests passed.'
