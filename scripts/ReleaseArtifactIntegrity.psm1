Set-StrictMode -Version Latest

function Get-HmReleaseArtifactNames {
    param([Parameter(Mandatory)][string]$ReleaseVersion)

    return @(
        "HDev.Hm.Logging.Contracts.$ReleaseVersion.nupkg",
        "HDev.Hm.Logging.Contracts.$ReleaseVersion.snupkg"
    )
}

function New-HmReleaseArtifactManifest {
    param(
        [Parameter(Mandatory)][string]$PackageDirectory,
        [Parameter(Mandatory)][string]$ReleaseVersion
    )

    $packageDirectory = (Resolve-Path -LiteralPath $PackageDirectory).Path
    $manifestPath = Join-Path $packageDirectory 'release-artifacts.sha256'
    $entries = foreach ($name in Get-HmReleaseArtifactNames -ReleaseVersion $ReleaseVersion) {
        $path = Join-Path $packageDirectory $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Release artifact '$name' was not produced." }
        "$((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()) *$name"
    }

    [System.IO.File]::WriteAllLines($manifestPath, $entries, [System.Text.UTF8Encoding]::new($false))
}

function Assert-HmReleaseArtifactManifest {
    param(
        [Parameter(Mandatory)][string]$PackageDirectory,
        [Parameter(Mandatory)][string]$ReleaseVersion
    )

    $packageDirectory = (Resolve-Path -LiteralPath $PackageDirectory).Path
    $manifestPath = Join-Path $packageDirectory 'release-artifacts.sha256'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'The release artifact integrity manifest was not produced.' }

    $expectedNames = @(Get-HmReleaseArtifactNames -ReleaseVersion $ReleaseVersion)
    $lines = @(Get-Content -LiteralPath $manifestPath)
    if ($lines.Count -ne $expectedNames.Count) { throw 'The release artifact integrity manifest has an unexpected number of entries.' }

    foreach ($name in $expectedNames) {
        $line = $lines | Where-Object { $_ -match "^[0-9a-f]{64} \*$([regex]::Escape($name))$" }
        if (@($line).Count -ne 1) { throw "The release artifact integrity manifest is missing '$name'." }
        $actualHash = (Get-FileHash -LiteralPath (Join-Path $packageDirectory $name) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($line.Substring(0, 64) -cne $actualHash) { throw "Release artifact '$name' does not match the validated artifact integrity manifest." }
    }
}

Export-ModuleMember -Function Get-HmReleaseArtifactNames, New-HmReleaseArtifactManifest, Assert-HmReleaseArtifactManifest
