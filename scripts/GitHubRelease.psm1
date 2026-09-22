Set-StrictMode -Version Latest

function Resolve-HmGitHubReleaseLookup {
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][bool]$ExpectedPrerelease,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string[]]$Output
    )

    $text = ($Output -join [Environment]::NewLine).Trim()
    if ($ExitCode -ne 0) {
        if ($text -ceq 'release not found') {
            return [pscustomobject]@{ State = 'absent' }
        }

        throw "GitHub Release lookup for '$Tag' failed: $text"
    }

    try { $release = $text | ConvertFrom-Json } catch { throw "GitHub Release lookup for '$Tag' returned malformed JSON." }
    if ($release.tagName -cne $Tag) { throw "GitHub Release lookup returned an unexpected tag identity for '$Tag'." }
    if ([bool]$release.isPrerelease -ne $ExpectedPrerelease) { throw "GitHub Release '$Tag' has an unexpected prerelease state." }

    return [pscustomobject]@{ State = 'existing' }
}

function Get-HmGitHubReleaseCreateArguments {
    param(
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][bool]$Prerelease
    )

    $arguments = @('release', 'create', $Tag, '--repo', $Repository, '--title', $Tag, '--generate-notes', '--verify-tag')
    if ($Prerelease) { $arguments += '--prerelease' }
    return $arguments
}

Export-ModuleMember -Function Get-HmGitHubReleaseCreateArguments, Resolve-HmGitHubReleaseLookup
