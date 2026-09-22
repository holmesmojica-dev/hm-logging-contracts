Set-StrictMode -Version Latest

function Get-HmBsrSourceControlUrl {
    param([Parameter(Mandatory)][string]$Commit)

    return "https://github.com/holmesmojica-dev/hm-logging-contracts/commit/$Commit"
}

function Resolve-HmBsrCommitLookup {
    param(
        [Parameter(Mandatory)][string]$Reference,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string[]]$Output
    )

    $text = ($Output -join [Environment]::NewLine).Trim()
    if ($ExitCode -ne 0) {
        $notFoundPattern = '^Failure: "' + [regex]::Escape($Reference) + '" does not exist$'
        if ($text -match $notFoundPattern) {
            return [pscustomobject]@{ State = 'absent'; CommitId = $null }
        }

        throw "BSR resolution for '$Reference' failed: $text"
    }

    try { $resolved = $text | ConvertFrom-Json } catch { throw "BSR resolution for '$Reference' returned malformed JSON." }
    if ($null -eq $resolved.commit -or $resolved.commit -cnotmatch '^[0-9a-f]{32}$') {
        throw "BSR resolution for '$Reference' did not return a valid immutable commit ID."
    }

    return [pscustomobject]@{ State = 'existing'; CommitId = [string]$resolved.commit }
}

function Assert-HmBsrCommitSourceIdentity {
    param(
        [Parameter(Mandatory)][string]$CommitId,
        [Parameter(Mandatory)][string]$ExpectedSourceControlUrl,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string[]]$Output
    )

    if ($ExitCode -ne 0) { throw "BSR commit information lookup for '$CommitId' failed: $(($Output -join [Environment]::NewLine).Trim())" }
    try { $info = (($Output -join [Environment]::NewLine).Trim() | ConvertFrom-Json) } catch { throw "BSR commit information for '$CommitId' returned malformed JSON." }
    if ($info.commit -cne $CommitId) { throw "BSR commit information did not identify immutable commit '$CommitId'." }
    if ([string]::IsNullOrWhiteSpace($info.source_control_url)) { throw "BSR commit '$CommitId' does not contain source_control_url." }
    if ($info.source_control_url -cne $ExpectedSourceControlUrl) { throw "BSR commit '$CommitId' has a conflicting source_control_url." }
}

Export-ModuleMember -Function Assert-HmBsrCommitSourceIdentity, Get-HmBsrSourceControlUrl, Resolve-HmBsrCommitLookup
