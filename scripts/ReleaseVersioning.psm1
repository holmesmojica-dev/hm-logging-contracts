Set-StrictMode -Version Latest

function Test-HmCanonicalNonNegativeInteger {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    return $Value -eq '0' -or $Value -match '^[1-9][0-9]*$'
}

function Get-HmReleaseVersionFromTag {
    param(
        [Parameter(Mandatory)]
        [string]$Tag
    )

    if (-not $Tag.StartsWith('v', [System.StringComparison]::Ordinal)) {
        throw "Release tag '$Tag' must use the canonical v<SemVer> form."
    }

    $releaseVersion = $Tag.Substring(1)
    if ([string]::IsNullOrWhiteSpace($releaseVersion)) {
        throw "Release tag '$Tag' must include a SemVer version after 'v'."
    }

    if ($releaseVersion.Contains('+', [System.StringComparison]::Ordinal)) {
        throw "Release tag '$Tag' must not contain SemVer build metadata."
    }

    return $releaseVersion
}

function Split-HmReleaseVersion {
    param(
        [Parameter(Mandatory)]
        [string]$ReleaseVersion
    )

    $prereleaseSeparator = $releaseVersion.IndexOf('-', [System.StringComparison]::Ordinal)
    if ($prereleaseSeparator -lt 0) {
        return [pscustomobject]@{
            CoreVersion = $releaseVersion
            HasPrerelease = $false
            Prerelease = $null
        }
    }

    return [pscustomobject]@{
        CoreVersion = $releaseVersion.Substring(0, $prereleaseSeparator)
        HasPrerelease = $true
        Prerelease = $releaseVersion.Substring($prereleaseSeparator + 1)
    }
}

function Assert-HmCanonicalCoreVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Tag,

        [Parameter(Mandatory)]
        [string]$CoreVersion
    )

    $coreIdentifiers = $coreVersion.Split('.')
    if ($coreIdentifiers.Count -ne 3) {
        throw "Release tag '$Tag' must contain a canonical major.minor.patch version."
    }

    foreach ($identifier in $coreIdentifiers) {
        if (-not (Test-HmCanonicalNonNegativeInteger $identifier)) {
            throw "Release tag '$Tag' must contain a canonical major.minor.patch version."
        }
    }
}

function Assert-HmPrereleaseIdentifiers {
    param(
        [Parameter(Mandatory)]
        [string]$Tag,

        [Parameter()]
        [bool]$HasPrerelease,

        [Parameter()]
        [string]$Prerelease
    )

    if (-not $HasPrerelease) {
        return
    }

    if ([string]::IsNullOrEmpty($prerelease)) {
        throw "Release tag '$Tag' has an empty prerelease identifier."
    }

    foreach ($identifier in $prerelease.Split('.')) {
        if ([string]::IsNullOrEmpty($identifier) -or $identifier -notmatch '^[0-9A-Za-z-]+$') {
            throw "Release tag '$Tag' has an invalid prerelease identifier."
        }

        if ($identifier -match '^[0-9]+$' -and -not (Test-HmCanonicalNonNegativeInteger $identifier)) {
            throw "Release tag '$Tag' has a prerelease numeric identifier with a leading zero."
        }
    }
}

function Resolve-HmReleaseTag {
    param(
        [Parameter(Mandatory)]
        [string]$Tag
    )

    $releaseVersion = Get-HmReleaseVersionFromTag -Tag $Tag
    $components = Split-HmReleaseVersion -ReleaseVersion $releaseVersion
    Assert-HmCanonicalCoreVersion -Tag $Tag -CoreVersion $components.CoreVersion
    Assert-HmPrereleaseIdentifiers -Tag $Tag -HasPrerelease $components.HasPrerelease -Prerelease $components.Prerelease

    return [pscustomobject]@{
        Tag = $Tag
        ReleaseVersion = $releaseVersion
    }
}

function Assert-HmReleaseVersion {
    param(
        [Parameter(Mandatory)]
        [string]$ReleaseVersion
    )

    $release = Resolve-HmReleaseTag -Tag "v$ReleaseVersion"
    if ($release.ReleaseVersion -ne $ReleaseVersion) {
        throw "ReleaseVersion '$ReleaseVersion' is not canonical."
    }

    return $release
}

function Get-HmReleaseTagCommit {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryPath,

        [Parameter(Mandatory)]
        [string]$Tag
    )

    $commitOutput = & git -C $RepositoryPath rev-parse --verify "$Tag^{commit}"
    if ($LASTEXITCODE -ne 0) {
        throw "Release tag '$Tag' does not resolve to a commit in '$RepositoryPath'."
    }

    $commit = ($commitOutput | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($commit)) {
        throw "Release tag '$Tag' does not resolve to a commit in '$RepositoryPath'."
    }

    return $commit
}

function Assert-HmCommitInMainHistory {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryPath,

        [Parameter(Mandatory)]
        [string]$Commit,

        [Parameter(Mandatory)]
        [string]$MainBranch
    )

    & git -C $RepositoryPath rev-parse --verify "$MainBranch^{commit}" *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Main branch reference '$MainBranch' does not resolve to a commit in '$RepositoryPath'."
    }

    & git -C $RepositoryPath merge-base --is-ancestor $Commit $MainBranch
    if ($LASTEXITCODE -ne 0) {
        throw "Tagged commit '$Commit' is not in the history of '$MainBranch'."
    }
}

function Assert-HmCheckedOutCommit {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryPath,

        [Parameter(Mandatory)]
        [string]$Commit
    )

    $checkedOutCommit = (& git -C $RepositoryPath rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $checkedOutCommit -ne $Commit) {
        throw "The checked-out commit '$checkedOutCommit' does not match release commit '$Commit'."
    }
}

function Resolve-HmReleaseContext {
    param(
        [Parameter(Mandatory)]
        [string]$RepositoryPath,

        [Parameter(Mandatory)]
        [string]$Tag,

        [Parameter()]
        [string]$MainBranch = 'main'
    )

    $release = Resolve-HmReleaseTag -Tag $Tag
    $commit = Get-HmReleaseTagCommit -RepositoryPath $RepositoryPath -Tag $release.Tag
    Assert-HmCommitInMainHistory -RepositoryPath $RepositoryPath -Commit $commit -MainBranch $MainBranch

    return [pscustomobject]@{
        Tag = $release.Tag
        ReleaseVersion = $release.ReleaseVersion
        Commit = $commit
    }
}

Export-ModuleMember -Function Assert-HmCheckedOutCommit, Assert-HmCommitInMainHistory, Assert-HmReleaseVersion, Resolve-HmReleaseTag, Resolve-HmReleaseContext
