[CmdletBinding()]
param([Parameter(Mandatory)][string]$CommitId)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($CommitId -cnotmatch '^[0-9a-f]{32}$') { throw 'A valid immutable BSR commit ID is required.' }
if ([string]::IsNullOrWhiteSpace($env:GH_VARIABLES_TOKEN)) { throw 'GH_VARIABLES_TOKEN must be supplied to persist BSR state.' }

$headers = @{ Accept = 'application/vnd.github+json'; Authorization = "Bearer $env:GH_VARIABLES_TOKEN"; 'X-GitHub-Api-Version' = '2022-11-28' }
$uri = "https://api.github.com/repos/$env:GITHUB_REPOSITORY/actions/variables/LAST_BSR_COMMIT_ID"
for ($attempt = 1; $attempt -le 2; $attempt++) {
    try {
        Invoke-RestMethod -Method Patch -Uri $uri -Headers $headers -ContentType 'application/json' -Body (@{ name = 'LAST_BSR_COMMIT_ID'; value = $CommitId } | ConvertTo-Json) -TimeoutSec 15
        return
    }
    catch {
        if ($attempt -eq 2) { throw }
        Start-Sleep -Seconds 10
    }
}
