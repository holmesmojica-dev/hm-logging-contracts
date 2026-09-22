[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PackageDirectory,
    [Parameter(Mandatory)][string]$ReleaseVersion,
    [Parameter(Mandatory)][string]$Commit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression

$packageDirectory = (Resolve-Path $PackageDirectory).Path
$packageName = "HDev.Hm.Logging.Contracts.$ReleaseVersion.nupkg"
$symbolName = "HDev.Hm.Logging.Contracts.$ReleaseVersion.snupkg"
$packagePath = Join-Path $packageDirectory $packageName
$symbolPath = Join-Path $packageDirectory $symbolName
if (-not (Test-Path $packagePath) -or -not (Test-Path $symbolPath)) { throw 'The expected .nupkg and .snupkg release artifacts were not produced.' }

$archive = [System.IO.Compression.ZipFile]::OpenRead($packagePath)
try {
    $entries = @($archive.Entries.FullName)
    foreach ($entry in @('README.md', 'LICENSE', 'icon.png', 'lib/net10.0/Hm.Logging.Contracts.dll', 'lib/net10.0/Hm.Logging.Contracts.xml', 'content/protos/hm/logging/contracts/v1/logging.proto', 'content/protos/hm/logging/contracts/v1/flow.proto', 'content/protos/hm/logging/contracts/v1/service.proto')) {
        if ($entries -notcontains $entry) { throw "Release package is missing '$entry'." }
    }
    if ($entries | Where-Object { $_ -match '^(build|buildTransitive)/|^content/protos/google/' }) { throw 'Release package contains prohibited automatic-consumption or external Google schema content.' }
    $nuspecEntry = $archive.Entries | Where-Object FullName -eq 'HDev.Hm.Logging.Contracts.nuspec'
    $reader = [System.IO.StreamReader]::new($nuspecEntry.Open())
    try { [xml]$nuspec = $reader.ReadToEnd() } finally { $reader.Dispose() }
    if ($nuspec.package.metadata.version -ne $ReleaseVersion -or $nuspec.package.metadata.repository.commit -ne $Commit) { throw 'Release package metadata does not match the release identity and source commit.' }
}
finally { $archive.Dispose() }

$symbols = [System.IO.Compression.ZipFile]::OpenRead($symbolPath)
try { if (-not ($symbols.Entries.FullName -match '\.pdb$')) { throw 'The symbol package does not contain a portable PDB.' } }
finally { $symbols.Dispose() }
