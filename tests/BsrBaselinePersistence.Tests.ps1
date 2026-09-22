[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\scripts\BsrValidation.psm1') -Force

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) { throw "$Message Expected '$Expected', received '$Actual'." }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    try { & $Action } catch { return }
    throw "$Message Expected an exception."
}

function Invoke-BaselinePersistenceScenario {
    param(
        [Parameter(Mandatory)]
        [int]$FailuresBeforeSuccess,

        [Parameter(Mandatory)]
        [string]$CommitId
    )

    $state = @{
        Attempts = 0
        Delays = [System.Collections.Generic.List[int]]::new()
        Requests = [System.Collections.Generic.List[object]]::new()
        FailuresBeforeSuccess = $FailuresBeforeSuccess
    }
    $persistenceAction = {
        param($Uri, $Headers, $Body, [int]$TimeoutSeconds)
        $state.Attempts++
        $state.Requests.Add([pscustomobject]@{ Uri = $Uri; Headers = $Headers; Body = $Body; TimeoutSeconds = $TimeoutSeconds })
        if ($state.Attempts -le $state.FailuresBeforeSuccess) { throw 'Simulated persistence failure.' }
    }.GetNewClosure()
    $delayAction = {
        param([int]$Seconds)
        $state.Delays.Add($Seconds)
    }.GetNewClosure()

    try {
        & (Join-Path $PSScriptRoot '..\scripts\Update-BsrBaseline.ps1') -CommitId $CommitId -PersistenceAction $persistenceAction -DelayAction $delayAction
        return [pscustomobject]@{ Succeeded = $true; Attempts = $state.Attempts; Delays = $state.Delays; Requests = $state.Requests }
    }
    catch {
        return [pscustomobject]@{ Succeeded = $false; Attempts = $state.Attempts; Delays = $state.Delays; Requests = $state.Requests }
    }
}

$commitId = '0123456789abcdef0123456789abcdef'
$baselineScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\scripts\Update-BsrBaseline.ps1') -Raw
Assert-True ($baselineScript -match 'for \(\$attempt = 1; \$attempt -le 2; \$attempt\+\+\)') 'Persistence must retain two total attempts.'

$initialBaseline = Resolve-HmBsrCompatibilityBaseline -LastBsrCommitId 'INITIAL'
Assert-Equal 'Initial' $initialBaseline.Mode 'INITIAL must remain valid only as the pre-publication baseline state.'

$successful = Invoke-BaselinePersistenceScenario -FailuresBeforeSuccess 0 -CommitId $commitId
Assert-True $successful.Succeeded 'A valid immutable BSR commit ID must persist successfully.'
Assert-Equal 1 $successful.Attempts 'Successful persistence must mutate exactly once.'
Assert-Equal 0 $successful.Delays.Count 'Successful persistence must not delay.'
Assert-Equal 1 $successful.Requests.Count 'Successful persistence must issue exactly one request.'
Assert-Equal 15 $successful.Requests[0].TimeoutSeconds 'Each persistence attempt must retain its fifteen-second timeout.'
$successfulBody = $successful.Requests[0].Body | ConvertFrom-Json
Assert-Equal 'LAST_BSR_COMMIT_ID' $successfulBody.name 'Persistence must target LAST_BSR_COMMIT_ID.'
Assert-Equal $commitId $successfulBody.value 'Persistence must store the exact immutable BSR commit ID.'

$transientFailure = Invoke-BaselinePersistenceScenario -FailuresBeforeSuccess 1 -CommitId $commitId
Assert-True $transientFailure.Succeeded 'A transient persistence failure must retry and succeed.'
Assert-Equal 2 $transientFailure.Attempts 'A transient persistence failure must use two total attempts.'
Assert-True (@($transientFailure.Requests | Where-Object { $_.TimeoutSeconds -ne 15 }).Count -eq 0) 'Each retry attempt must retain its fifteen-second timeout.'
Assert-Equal 1 $transientFailure.Delays.Count 'A transient persistence failure must delay once.'
Assert-Equal 10 $transientFailure.Delays[0] 'The retry delay must remain ten seconds.'

$exhaustedFailure = Invoke-BaselinePersistenceScenario -FailuresBeforeSuccess 2 -CommitId $commitId
Assert-True (-not $exhaustedFailure.Succeeded) 'Two persistence failures must fail the operation.'
Assert-Equal 2 $exhaustedFailure.Attempts 'Exhausted retry must use two total attempts.'
Assert-Equal 1 $exhaustedFailure.Delays.Count 'Exhausted retry must delay only between attempts.'
Assert-Equal 10 $exhaustedFailure.Delays[0] 'The exhausted retry delay must remain ten seconds.'

$mutationAttempted = $false
$noMutation = { param($Uri, $Headers, $Body) $script:mutationAttempted = $true }
foreach ($invalidCommitId in @('INITIAL', '0123456789ABCDEF0123456789ABCDEF', 'not-a-bsr-commit', '0123456789abcdef')) {
    $script:mutationAttempted = $false
    Assert-Throws {
        & (Join-Path $PSScriptRoot '..\scripts\Update-BsrBaseline.ps1') -CommitId $invalidCommitId -PersistenceAction $noMutation
    } "Invalid publication commit identity '$invalidCommitId' was accepted."
    Assert-True (-not $script:mutationAttempted) "Invalid publication commit identity '$invalidCommitId' attempted remote persistence."
}

Write-Output 'BSR baseline persistence tests passed.'
