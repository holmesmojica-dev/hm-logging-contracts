[CmdletBinding()]
param(
    [switch]$NoRestore,
    [switch]$NoBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = (& git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'The coverage script must run from within a Git repository.'
}

$coverageDirectory = Join-Path $repositoryRoot 'TestResults/coverage'
New-Item -ItemType Directory -Path $coverageDirectory -Force | Out-Null

$arguments = @(
    'test',
    'Hm.Logging.Contracts.slnx',
    '--configuration',
    'Debug',
    '--coverage',
    '--coverage-output-format',
    'xml',
    '--coverage-output',
    (Join-Path $coverageDirectory 'coverage.xml'),
    '--coverage-settings',
    (Join-Path $repositoryRoot 'scripts/code-coverage.settings.xml')
)

if ($NoRestore) {
    $arguments += '--no-restore'
}

if ($NoBuild) {
    $arguments += '--no-build'
}

Write-Host "==> dotnet $($arguments -join ' ')"
& dotnet @arguments
if ($LASTEXITCODE -ne 0) {
    throw "Coverage test run failed with exit code $LASTEXITCODE."
}
