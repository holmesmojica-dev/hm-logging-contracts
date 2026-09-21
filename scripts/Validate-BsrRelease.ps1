[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Tag,

    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string]$LastBsrCommitId,

    [Parameter()]
    [string]$RepositoryPath = (Split-Path $PSScriptRoot -Parent),

    [Parameter()]
    [string]$MainBranch = 'main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ReleaseVersioning.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'BsrValidation.psm1') -Force

function Invoke-BufCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    & buf @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Buf command 'buf $($Arguments -join ' ')' failed with exit code $LASTEXITCODE."
    }
}

if (-not (Get-Command buf -ErrorAction SilentlyContinue)) {
    throw "Required command 'buf' was not found on PATH."
}

$repositoryPath = (Resolve-Path $RepositoryPath).Path
$release = Resolve-HmReleaseContext -RepositoryPath $repositoryPath -Tag $Tag -MainBranch $MainBranch
Assert-HmCheckedOutCommit -RepositoryPath $repositoryPath -Commit $release.Commit
$releaseLabel = Resolve-HmBsrReleaseLabel -Tag $release.Tag
$baseline = Resolve-HmBsrCompatibilityBaseline -LastBsrCommitId $LastBsrCommitId

Push-Location $repositoryPath
try {
    $moduleNames = @(Invoke-BufCommand -Arguments @('config', 'ls-modules', '--format', 'name'))
    Assert-HmBsrModuleConfiguration -ModuleNames $moduleNames

    Invoke-BufCommand -Arguments @('format', 'proto', '--exit-code')
    Invoke-BufCommand -Arguments @('lint')
    Invoke-BufCommand -Arguments @('build')
    & (Join-Path $PSScriptRoot 'Validate-BufLock.ps1') -RepositoryPath $repositoryPath

    $breakingRan = Invoke-HmBsrBreakingValidation -Baseline $baseline -BufCommandInvoker {
        param([string[]]$Arguments)
        Invoke-BufCommand -Arguments $Arguments
    }
    if (-not $breakingRan) {
        Write-Output 'LAST_BSR_COMMIT_ID=INITIAL: intentionally establishing the first compatibility baseline.'
    }

    Write-Output "BSR release preflight passed for '$releaseLabel' at Git commit '$($release.Commit)'."
}
finally {
    Pop-Location
}
