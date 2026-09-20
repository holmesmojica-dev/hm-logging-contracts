[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (& git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'The hook installer must run from within a Git repository.'
}

$hookPath = Join-Path $repositoryRoot 'hooks/pre-commit'
if (-not (Test-Path $hookPath -PathType Leaf)) {
    throw "Repository-managed pre-commit hook was not found at '$hookPath'."
}

& git -C $repositoryRoot config --local core.hooksPath hooks
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to configure the repository-local Git hooks path.'
}

Write-Host 'Repository-managed Git hooks are enabled through local core.hooksPath=hooks.'
