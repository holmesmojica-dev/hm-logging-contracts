[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\scripts\GitHubRelease.psm1') -Force

function Assert-Equal {
    param($Expected, $Actual)
    if ($Expected -ne $Actual) { throw "Expected '$Expected', received '$Actual'." }
}

function Assert-Throws {
    param([scriptblock]$Action)
    try { & $Action } catch { return }
    throw 'Expected an exception.'
}

$tag = 'v1.0.0-preview.1'
$existing = Resolve-HmGitHubReleaseLookup -Tag $tag -ExpectedPrerelease $true -ExitCode 0 -Output @('{"tagName":"v1.0.0-preview.1","isPrerelease":true}')
Assert-Equal 'existing' $existing.State

$absent = Resolve-HmGitHubReleaseLookup -Tag $tag -ExpectedPrerelease $true -ExitCode 1 -Output @('release not found')
Assert-Equal 'absent' $absent.State

Assert-Throws { Resolve-HmGitHubReleaseLookup -Tag $tag -ExpectedPrerelease $true -ExitCode 1 -Output @('HTTP 401') }
Assert-Throws { Resolve-HmGitHubReleaseLookup -Tag $tag -ExpectedPrerelease $true -ExitCode 0 -Output @('{"tagName":"v1.0.0","isPrerelease":true}') }
Assert-Throws { Resolve-HmGitHubReleaseLookup -Tag $tag -ExpectedPrerelease $true -ExitCode 0 -Output @('{"tagName":"v1.0.0-preview.1","isPrerelease":false}') }

$prereleaseArguments = Get-HmGitHubReleaseCreateArguments -Tag $tag -Repository 'owner/repository' -Prerelease $true
Assert-Equal $true ($prereleaseArguments -contains '--prerelease')
Assert-Equal $true ($prereleaseArguments -contains '--generate-notes')
Assert-Equal $true ($prereleaseArguments -contains '--verify-tag')

$stableArguments = Get-HmGitHubReleaseCreateArguments -Tag 'v1.0.0' -Repository 'owner/repository' -Prerelease $false
Assert-Equal $false ($stableArguments -contains '--prerelease')

Write-Output 'GitHub Release tests passed.'
