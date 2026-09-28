[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "hm-nuget-content-tests-$([Guid]::NewGuid())"
$version = '1.0.0-preview.1'
$commit = '1234567890123456789012345678901234567890'
$packageName = "HDev.Hm.Logging.Contracts.$version.nupkg"
$realDotnet = (Get-Command dotnet -CommandType Application | Select-Object -First 1).Source
$previousKey = $env:NUGET_TRUSTED_PUBLISHING_API_KEY
$global:HmNuGetContentTest = @{ Dotnet = $realDotnet }

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function New-TestPackage {
    param([string]$Path, [string]$Payload, [switch]$Symbols)
    $archive = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $entries = if ($Symbols) { @{ 'lib/net10.0/Hm.Logging.Contracts.pdb' = 'test symbols' } } else {
            @{
                'HDev.Hm.Logging.Contracts.nuspec' = "<package><metadata><id>HDev.Hm.Logging.Contracts</id><version>$version</version><repository commit='$commit'/></metadata></package>"
                'README.md' = 'test readme'
                'LICENSE' = 'test license'
                'icon.png' = 'test icon'
                'lib/net10.0/Hm.Logging.Contracts.dll' = $Payload
                'lib/net10.0/Hm.Logging.Contracts.xml' = 'test docs'
                'content/protos/hm/logging/contracts/v1/logging.proto' = 'test schema'
                'content/protos/hm/logging/contracts/v1/flow.proto' = 'test schema'
                'content/protos/hm/logging/contracts/v1/service.proto' = 'test schema'
            }
        }
        foreach ($name in $entries.Keys) {
            $writer = [System.IO.StreamWriter]::new($archive.CreateEntry($name).Open())
            try { $writer.Write($entries[$name]) } finally { $writer.Dispose() }
        }
    }
    finally { $archive.Dispose() }
}

# Shadow only the external boundaries in this isolated test process. Neither
# download nor push can reach the network; the actual content tool still runs.
function global:Invoke-WebRequest {
    param($Uri, $OutFile, $TimeoutSec)
    $global:HmNuGetContentTest.Events.Add('download')
    Copy-Item -LiteralPath $global:HmNuGetContentTest.RemoteFixture -Destination $OutFile
}

function global:dotnet {
    if ($args[0] -eq 'nuget' -and $args[1] -eq 'push') {
        $global:HmNuGetContentTest.Events.Add('push')
        $global:LASTEXITCODE = 0
        return
    }
    if ($args[0] -ne 'run' -or $args -notcontains 'assert-content-identity') {
        throw 'Unexpected dotnet invocation; no external command is allowed.'
    }
    if (Test-Path -LiteralPath $global:HmNuGetContentTest.Output) { throw 'A successful state was emitted before content verification.' }
    $global:HmNuGetContentTest.Events.Add('content')
    # The canonical validation builds the tool first. Do not restore/build or
    # contact any feed from these behavioral tests.
    $toolArguments = @($args | Select-Object -Skip 1)
    & $global:HmNuGetContentTest.Dotnet run --no-build --no-restore @toolArguments
    $global:LASTEXITCODE = $LASTEXITCODE
}

try {
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
    $localDirectory = Join-Path $temporaryDirectory 'local'
    New-Item -ItemType Directory -Path $localDirectory | Out-Null
    $localPackage = Join-Path $localDirectory $packageName
    New-TestPackage -Path $localPackage -Payload 'validated payload'
    New-TestPackage -Path (Join-Path $localDirectory "HDev.Hm.Logging.Contracts.$version.snupkg") -Symbols
    & (Join-Path $repositoryRoot 'scripts/New-ReleaseArtifactManifest.ps1') -PackageDirectory $localDirectory -ReleaseVersion $version
    $equivalent = Join-Path $temporaryDirectory 'equivalent.nupkg'
    Copy-Item -LiteralPath $localPackage -Destination $equivalent
    $different = Join-Path $temporaryDirectory 'different.nupkg'
    New-TestPackage -Path $different -Payload 'conflicting payload'
    $env:NUGET_TRUSTED_PUBLISHING_API_KEY = 'local-test-only'

    foreach ($scriptName in @('Resolve-NuGetRelease.ps1', 'Publish-NuGetRelease.ps1')) {
        foreach ($contentMatches in @($true, $false)) {
            $remoteFixture = if ($contentMatches) { $equivalent } else { $different }
            $output = Join-Path $temporaryDirectory "$scriptName-$contentMatches.output"
            $events = [System.Collections.Generic.List[string]]::new()
            $global:HmNuGetContentTest.RemoteFixture = $remoteFixture
            $global:HmNuGetContentTest.Output = $output
            $global:HmNuGetContentTest.Events = $events
            $failure = $null
            try {
                & (Join-Path $repositoryRoot "scripts/$scriptName") -PackageDirectory $localDirectory -ReleaseVersion $version -Commit $commit -GitHubOutputPath $output
            }
            catch { $failure = $_ }
            if ($contentMatches) {
                Assert-True ($null -eq $failure) "Equivalent package failed: $failure"
                $state = if ($scriptName -eq 'Resolve-NuGetRelease.ps1') { 'already_verified' } else { 'published' }
                Assert-True ((Get-Content -LiteralPath $output) -contains "nuget_state=$state") "Expected $state."
            }
            else {
                Assert-True ($null -ne $failure) 'Conflicting content was accepted.'
                Assert-True (-not (Test-Path -LiteralPath $output)) 'Content failure emitted a successful state.'
            }
            $expectedEvents = if ($scriptName -eq 'Resolve-NuGetRelease.ps1') { 'download,content' } else { 'push,download,content' }
            Assert-True (($events -join ',') -ceq $expectedEvents) "Unexpected verification order: $($events -join ',')"
        }
    }
    Write-Output 'NuGet content recovery and fresh publication behavioral tests passed (local fakes only).'
}
finally {
    $env:NUGET_TRUSTED_PUBLISHING_API_KEY = $previousKey
    Remove-Item Function:\dotnet, Function:\Invoke-WebRequest
    Remove-Variable HmNuGetContentTest -Scope Global
    if (Test-Path -LiteralPath $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
}
