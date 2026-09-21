[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:BUF_TOKEN)) {
    throw 'BUF_TOKEN must be supplied for BSR authentication validation.'
}

if (-not (Get-Command buf -ErrorAction SilentlyContinue)) {
    throw "Required command 'buf' was not found on PATH."
}

& buf registry whoami
if ($LASTEXITCODE -ne 0) {
    throw "Buf command 'buf registry whoami' failed with exit code $LASTEXITCODE."
}
