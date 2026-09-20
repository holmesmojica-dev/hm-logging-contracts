[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-ValidationCommand {
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter()]
        [string[]]$Arguments = @(),

        [Parameter()]
        [switch]$SuppressOutput
    )

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Required command '$Command' was not found on PATH."
    }

    Write-Host "==> $Command $($Arguments -join ' ')"

    if ($SuppressOutput) {
        & $Command @Arguments | Out-Null
    }
    else {
        & $Command @Arguments
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Validation command '$Command' failed with exit code $LASTEXITCODE."
    }
}

$repositoryRoot = (& git rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($repositoryRoot)) {
    throw 'The validation script must run from within a Git repository.'
}

Push-Location $repositoryRoot
try {
    # Buf invokes diff for format verification. Git for Windows includes it, but
    # its Unix tools are not always present on the PowerShell PATH.
    if ($env:OS -eq 'Windows_NT' -and -not (Get-Command diff -ErrorAction SilentlyContinue)) {
        $gitPath = (Get-Command git -ErrorAction Stop).Source
        $gitRoot = Split-Path (Split-Path $gitPath -Parent) -Parent
        $gitUnixBin = Join-Path $gitRoot 'usr\bin'

        if (Test-Path (Join-Path $gitUnixBin 'diff.exe')) {
            $env:Path = "$gitUnixBin;$env:Path"
        }
    }

    Invoke-ValidationCommand -Command dotnet -Arguments @('restore', 'Hm.Logging.Contracts.slnx')
    Invoke-ValidationCommand -Command dotnet -Arguments @('format', 'Hm.Logging.Contracts.slnx', '--no-restore', '--verify-no-changes')
    Invoke-ValidationCommand -Command dotnet -Arguments @('build', 'Hm.Logging.Contracts.slnx', '--configuration', 'Release', '--no-restore')
    Invoke-ValidationCommand -Command dotnet -Arguments @('test', 'Hm.Logging.Contracts.slnx', '--configuration', 'Release', '--no-build', '--no-restore')
    Invoke-ValidationCommand -Command buf -Arguments @('format', 'proto', '--exit-code') -SuppressOutput
    Invoke-ValidationCommand -Command buf -Arguments @('lint')
    Invoke-ValidationCommand -Command buf -Arguments @('build')
}
finally {
    Pop-Location
}
