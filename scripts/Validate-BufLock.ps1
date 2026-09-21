[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryPath = (Split-Path $PSScriptRoot -Parent),

    [Parameter()]
    [string]$BufCommand = 'buf'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command $BufCommand -ErrorAction SilentlyContinue)) {
    throw "Required command '$BufCommand' was not found on PATH."
}

$repositoryPath = (Resolve-Path $RepositoryPath).Path
$temporaryWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) "hm-buf-lock-$([Guid]::NewGuid())"

try {
    New-Item -ItemType Directory -Path $temporaryWorkspace | Out-Null
    Copy-Item -LiteralPath (Join-Path $repositoryPath 'buf.yaml') -Destination $temporaryWorkspace
    Copy-Item -LiteralPath (Join-Path $repositoryPath 'buf.lock') -Destination $temporaryWorkspace
    Copy-Item -LiteralPath (Join-Path $repositoryPath 'proto') -Destination $temporaryWorkspace -Recurse

    & $BufCommand dep update $temporaryWorkspace --timeout 60s
    if ($LASTEXITCODE -ne 0) {
        throw 'Buf could not resolve the declared dependencies while validating buf.lock.'
    }

    $committedLock = [System.IO.File]::ReadAllBytes((Join-Path $repositoryPath 'buf.lock'))
    $resolvedLock = [System.IO.File]::ReadAllBytes((Join-Path $temporaryWorkspace 'buf.lock'))
    if ($committedLock.Length -ne $resolvedLock.Length -or -not [System.Linq.Enumerable]::SequenceEqual[byte]($committedLock, $resolvedLock)) {
        throw 'buf.lock is stale or inconsistent with buf.yaml. Run "buf dep update" and commit the generated buf.lock.'
    }
}
finally {
    if (Test-Path $temporaryWorkspace) {
        Remove-Item -LiteralPath $temporaryWorkspace -Recurse -Force
    }
}
