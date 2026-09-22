[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\scripts\ReleaseVersioning.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '..\scripts\BsrValidation.psm1') -Force

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        $Expected,

        [Parameter(Mandatory)]
        $Actual,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', received '$Actual'."
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [Parameter(Mandatory)]
        [string]$Message
    )

    try {
        & $Action
    }
    catch {
        return
    }

    throw "$Message Expected an exception."
}

$releaseVersioningModule = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\ReleaseVersioning.psm1')).Path
$bsrValidationModule = (Resolve-Path (Join-Path $PSScriptRoot '..\scripts\BsrValidation.psm1')).Path
$childCommand = @"
Import-Module '$releaseVersioningModule' -Force
Import-Module '$bsrValidationModule' -Force
Get-Command Resolve-HmReleaseContext -ErrorAction Stop | Out-Null
"@
$encodedChildCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childCommand))
& pwsh -NoProfile -EncodedCommand $encodedChildCommand
Assert-Equal -Expected 0 -Actual $LASTEXITCODE -Message 'A fresh PowerShell process lost Resolve-HmReleaseContext after importing BsrValidation.'

$initial = Resolve-HmBsrCompatibilityBaseline -LastBsrCommitId 'INITIAL'
Assert-Equal -Expected 'Initial' -Actual $initial.Mode -Message 'INITIAL did not select the explicit first-baseline mode.'

$commitId = '0123456789abcdef0123456789abcdef'
$published = Resolve-HmBsrCompatibilityBaseline -LastBsrCommitId $commitId
Assert-Equal -Expected 'Published' -Actual $published.Mode -Message 'A valid BSR commit ID did not select the published-baseline mode.'
Assert-Equal -Expected $commitId -Actual $published.CommitId -Message 'The BSR commit ID was not retained.'

$breakingArguments = $null
$breakingRan = Invoke-HmBsrBreakingValidation -Baseline $published -BufCommandInvoker {
    param([string[]]$Arguments)
    $script:breakingArguments = $Arguments
}
Assert-Equal -Expected $true -Actual $breakingRan -Message 'A published baseline did not require breaking validation.'
Assert-Equal -Expected "buf.build/hdev-hm/logging:$commitId" -Actual $breakingArguments[2] -Message 'Breaking validation did not target the immutable BSR baseline.'

Assert-Throws -Action {
    Invoke-HmBsrBreakingValidation -Baseline $published -BufCommandInvoker {
        param([string[]]$Arguments)
        throw "The immutable BSR commit '$($Arguments[2])' could not be resolved."
    }
} -Message 'An unresolvable BSR baseline did not block breaking validation.'

$initialBreakingCalled = $false
$initialBreakingRan = Invoke-HmBsrBreakingValidation -Baseline $initial -BufCommandInvoker {
    param([string[]]$Arguments)
    $script:initialBreakingCalled = $true
}
Assert-Equal -Expected $false -Actual $initialBreakingRan -Message 'INITIAL unexpectedly ran breaking validation.'
Assert-Equal -Expected $false -Actual $initialBreakingCalled -Message 'INITIAL invoked Buf breaking validation.'

foreach ($baseline in @('', ' ', 'initial', 'v1.0.0', '0123456789ABCDEF0123456789ABCDEF', '0123456789abcdef')) {
    Assert-Throws -Action { Resolve-HmBsrCompatibilityBaseline -LastBsrCommitId $baseline } -Message "Invalid baseline '$baseline' was accepted."
}

Assert-Equal -Expected 'v1.0.0-preview.1' -Actual (Resolve-HmBsrReleaseLabel -Tag 'v1.0.0-preview.1') -Message 'The BSR label did not preserve the release tag.'
Assert-Throws -Action { Resolve-HmBsrReleaseLabel -Tag 'main' } -Message 'A branch name was accepted as a BSR release label.'

Assert-HmBsrModuleConfiguration -ModuleNames @('buf.build/hdev-hm/logging')
Assert-Throws -Action { Assert-HmBsrModuleConfiguration -ModuleNames @('buf.build/hdev-hm/other') } -Message 'An incorrect BSR module name was accepted.'
Assert-Throws -Action { Assert-HmBsrModuleConfiguration -ModuleNames @('buf.build/hdev-hm/logging', 'buf.build/hdev-hm/other') } -Message 'Multiple BSR modules were accepted.'

Write-Output 'BSR validation tests passed.'
