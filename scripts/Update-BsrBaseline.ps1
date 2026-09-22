[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CommitId,

    [Parameter()]
    [scriptblock]$PersistenceAction,

    [Parameter()]
    [scriptblock]$DelayAction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($CommitId -cnotmatch '^[0-9a-f]{32}$') { throw 'A valid immutable BSR commit ID is required.' }

$uri = "https://api.github.com/repos/$env:GITHUB_REPOSITORY/actions/variables/LAST_BSR_COMMIT_ID"
$body = @{ name = 'LAST_BSR_COMMIT_ID'; value = $CommitId } | ConvertTo-Json
$headers = $null
$timeoutSeconds = 15

if ($null -eq $PersistenceAction) {
    if ([string]::IsNullOrWhiteSpace($env:GH_VARIABLES_TOKEN)) { throw 'GH_VARIABLES_TOKEN must be supplied to persist BSR state.' }

    $headers = @{ Accept = 'application/vnd.github+json'; Authorization = "Bearer $env:GH_VARIABLES_TOKEN"; 'X-GitHub-Api-Version' = '2022-11-28' }
    $PersistenceAction = {
        param($RequestUri, $RequestHeaders, $RequestBody, [int]$TimeoutSeconds)
        Invoke-RestMethod -Method Patch -Uri $RequestUri -Headers $RequestHeaders -ContentType 'application/json' -Body $RequestBody -TimeoutSec $TimeoutSeconds
    }
}

if ($null -eq $DelayAction) {
    $DelayAction = {
        param([int]$Seconds)
        Start-Sleep -Seconds $Seconds
    }
}

for ($attempt = 1; $attempt -le 2; $attempt++) {
    try {
        & $PersistenceAction $uri $headers $body $timeoutSeconds
        return
    }
    catch {
        if ($attempt -eq 2) { throw }
        & $DelayAction 10
    }
}
