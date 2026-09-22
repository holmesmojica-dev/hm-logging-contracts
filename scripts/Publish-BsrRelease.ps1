[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$GitHubOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BsrValidation.psm1') -Force
if ([string]::IsNullOrWhiteSpace($env:BUF_TOKEN)) { throw 'BUF_TOKEN must be supplied for BSR publication.' }
$moduleName = Get-HmBsrModuleName
$sourceUrl = "https://github.com/holmesmojica-dev/hm-logging-contracts/commit/$Commit"

for ($attempt = 1; $attempt -le 2; $attempt++) {
    & buf push --label $Tag --source-control-url $sourceUrl --timeout 60s
    if ($LASTEXITCODE -eq 0) { break }
    if ($attempt -eq 2) { throw 'BSR publication failed after two attempts.' }
    Start-Sleep -Seconds 10
}

$resolved = (& buf registry module commit resolve "${moduleName}:$Tag" --format json --timeout 60s | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $resolved.commit -cnotmatch '^[0-9a-f]{32}$') { throw 'BSR publication did not resolve to a valid immutable commit ID.' }

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "hm-bsr-release-$([Guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    $localDescriptor = Join-Path $temporaryDirectory 'local.binpb'
    $remoteDescriptor = Join-Path $temporaryDirectory 'remote.binpb'
    & buf build . --as-file-descriptor-set --output $localDescriptor
    if ($LASTEXITCODE -ne 0) { throw 'Buf could not build the validated local descriptor set.' }
    & buf build "${moduleName}:$($resolved.commit)" --as-file-descriptor-set --output $remoteDescriptor
    if ($LASTEXITCODE -ne 0) { throw 'Buf could not build the remote BSR descriptor set.' }
    if ((Get-FileHash $localDescriptor -Algorithm SHA256).Hash -ne (Get-FileHash $remoteDescriptor -Algorithm SHA256).Hash) { throw 'The immutable BSR commit is not semantically equivalent to the validated local descriptor set.' }
}
finally {
    if (Test-Path $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
}

@("release_version=$($Tag.Substring(1))", "source_commit=$Commit", 'bsr_state=published', "bsr_commit_id=$($resolved.commit)") | Add-Content -LiteralPath $GitHubOutputPath
