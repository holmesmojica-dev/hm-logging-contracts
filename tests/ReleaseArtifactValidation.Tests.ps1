[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression

$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "hm-release-artifact-$([Guid]::NewGuid())"
$releaseVersion = '1.0.0-preview.1'
$commit = '0123456789abcdef0123456789abcdef01234567'

function Add-ZipEntry {
    param([Parameter(Mandatory)]$Archive, [Parameter(Mandatory)][string]$Name, [string]$Content = '')
    $writer = [System.IO.StreamWriter]::new($Archive.CreateEntry($Name).Open())
    try { $writer.Write($Content) } finally { $writer.Dispose() }
}

try {
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    $package = Join-Path $temporaryDirectory "HDev.Hm.Logging.Contracts.$releaseVersion.nupkg"
    $symbols = Join-Path $temporaryDirectory "HDev.Hm.Logging.Contracts.$releaseVersion.snupkg"
    $archive = [System.IO.Compression.ZipFile]::Open($package, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        Add-ZipEntry $archive 'README.md'; Add-ZipEntry $archive 'LICENSE'; Add-ZipEntry $archive 'icon.png'
        Add-ZipEntry $archive 'lib/net10.0/Hm.Logging.Contracts.dll'; Add-ZipEntry $archive 'lib/net10.0/Hm.Logging.Contracts.xml'
        Add-ZipEntry $archive 'content/protos/hm/logging/contracts/v1/logging.proto'; Add-ZipEntry $archive 'content/protos/hm/logging/contracts/v1/flow.proto'; Add-ZipEntry $archive 'content/protos/hm/logging/contracts/v1/service.proto'
        Add-ZipEntry $archive 'HDev.Hm.Logging.Contracts.nuspec' ('<package><metadata><version>' + $releaseVersion + '</version><repository commit="' + $commit + '" /></metadata></package>')
    }
    finally { $archive.Dispose() }
    $symbolArchive = [System.IO.Compression.ZipFile]::Open($symbols, [System.IO.Compression.ZipArchiveMode]::Create)
    try { Add-ZipEntry $symbolArchive 'lib/net10.0/Hm.Logging.Contracts.pdb' } finally { $symbolArchive.Dispose() }

    & (Join-Path $PSScriptRoot '..\scripts\Validate-ReleaseArtifact.ps1') -PackageDirectory $temporaryDirectory -ReleaseVersion $releaseVersion -Commit $commit
}
finally {
    if (Test-Path $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
}

Write-Output 'Release artifact validation tests passed.'
