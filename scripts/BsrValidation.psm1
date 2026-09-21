Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'ReleaseVersioning.psm1') -Force

$HmBsrModuleName = 'buf.build/hdev-hm/logging'
$HmInitialBsrCommitId = 'INITIAL'

function Get-HmBsrModuleName {
    return $HmBsrModuleName
}

function Resolve-HmBsrCompatibilityBaseline {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$LastBsrCommitId
    )

    if ([string]::IsNullOrWhiteSpace($LastBsrCommitId)) {
        throw 'LAST_BSR_COMMIT_ID must be explicitly set to INITIAL or to an immutable BSR commit ID.'
    }

    if ($LastBsrCommitId -ceq $HmInitialBsrCommitId) {
        return [pscustomobject]@{
            Mode = 'Initial'
            CommitId = $null
        }
    }

    if ($LastBsrCommitId -cnotmatch '^[0-9a-f]{32}$') {
        throw "LAST_BSR_COMMIT_ID '$LastBsrCommitId' is not a valid immutable BSR commit ID."
    }

    return [pscustomobject]@{
        Mode = 'Published'
        CommitId = $LastBsrCommitId
    }
}

function Resolve-HmBsrReleaseLabel {
    param(
        [Parameter(Mandatory)]
        [string]$Tag
    )

    $release = Resolve-HmReleaseTag -Tag $Tag
    return $release.Tag
}

function Assert-HmBsrModuleConfiguration {
    param(
        [Parameter(Mandatory)]
        [string[]]$ModuleNames
    )

    if ($ModuleNames.Count -ne 1 -or $ModuleNames[0] -ne $HmBsrModuleName) {
        throw "Buf must configure exactly one module named '$HmBsrModuleName'."
    }
}

function Invoke-HmBsrBreakingValidation {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Baseline,

        [Parameter(Mandatory)]
        [scriptblock]$BufCommandInvoker
    )

    if ($Baseline.Mode -eq 'Initial') {
        return $false
    }

    & $BufCommandInvoker @('breaking', '--against', "${HmBsrModuleName}:$($Baseline.CommitId)")
    return $true
}

Export-ModuleMember -Function Assert-HmBsrModuleConfiguration, Get-HmBsrModuleName, Invoke-HmBsrBreakingValidation, Resolve-HmBsrCompatibilityBaseline, Resolve-HmBsrReleaseLabel
