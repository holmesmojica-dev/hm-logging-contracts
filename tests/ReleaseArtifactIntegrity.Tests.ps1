[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\scripts\ReleaseArtifactIntegrity.psm1') -Force

function Assert-Throws {
    param([scriptblock]$Action)
    try { & $Action } catch { return }
    throw 'Expected an exception.'
}

$directory = Join-Path ([System.IO.Path]::GetTempPath()) "hm-release-artifact-integrity-$([Guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path $directory | Out-Null
    foreach ($name in Get-HmReleaseArtifactNames -ReleaseVersion '1.0.0-preview.1') {
        [System.IO.File]::WriteAllText((Join-Path $directory $name), $name)
    }

    New-HmReleaseArtifactManifest -PackageDirectory $directory -ReleaseVersion '1.0.0-preview.1'
    Assert-HmReleaseArtifactManifest -PackageDirectory $directory -ReleaseVersion '1.0.0-preview.1'
    [System.IO.File]::AppendAllText((Join-Path $directory 'HDev.Hm.Logging.Contracts.1.0.0-preview.1.nupkg'), 'changed')
    Assert-Throws { Assert-HmReleaseArtifactManifest -PackageDirectory $directory -ReleaseVersion '1.0.0-preview.1' }
}
finally {
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
}

Write-Output 'Release artifact integrity tests passed.'
