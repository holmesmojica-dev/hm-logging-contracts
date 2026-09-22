[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\scripts\BsrPublication.psm1') -Force

function Assert-Equal {
    param($Expected, $Actual)
    if ($Expected -ne $Actual) { throw "Expected '$Expected', received '$Actual'." }
}

function Assert-Throws {
    param([scriptblock]$Action)
    try { & $Action } catch { return }
    throw 'Expected an exception.'
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-LoggedCommandIndex {
    param([string[]]$Log, [string]$Prefix)

    for ($index = 0; $index -lt $Log.Count; $index++) {
        if ($Log[$index].StartsWith($Prefix, [System.StringComparison]::Ordinal)) { return $index }
    }
    return -1
}

function Get-FakeBufScript {
    return @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CommandArguments)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Content -LiteralPath $env:HM_FAKE_BUF_LOG -Value ($CommandArguments -join '|')

if ($CommandArguments[0] -eq 'registry' -and $CommandArguments[3] -eq 'resolve') {
    $resolveCount = if (Test-Path -LiteralPath $env:HM_FAKE_BUF_RESOLVE_COUNT) {
        [int](Get-Content -LiteralPath $env:HM_FAKE_BUF_RESOLVE_COUNT -Raw)
    }
    else { 0 }
    $resolveCount++
    Set-Content -LiteralPath $env:HM_FAKE_BUF_RESOLVE_COUNT -Value $resolveCount -NoNewline

    if ($env:HM_FAKE_BUF_SCENARIO -eq 'absent' -and $resolveCount -eq 1) {
        Write-Output "Failure: `"$($CommandArguments[4])`" does not exist"
        exit 1
    }
    if ($env:HM_FAKE_BUF_SCENARIO -eq 'lookup-failure') {
        Write-Output 'Failure: unavailable'
        exit 1
    }

    Write-Output "{`"commit`":`"$env:HM_FAKE_BUF_COMMIT_ID`"}"
    exit 0
}

if ($CommandArguments[0] -eq 'registry' -and $CommandArguments[3] -eq 'info') {
    $sourceUrl = if ($env:HM_FAKE_BUF_SCENARIO -eq 'conflicting-source') {
        'https://example.invalid/conflicting-source'
    }
    else { $env:HM_FAKE_BUF_SOURCE_URL }
    Write-Output "{`"commit`":`"$env:HM_FAKE_BUF_COMMIT_ID`",`"source_control_url`":`"$sourceUrl`"}"
    exit 0
}

if ($CommandArguments[0] -eq 'push') { exit 0 }

if ($CommandArguments[0] -eq 'build') {
    $outputIndex = [array]::IndexOf($CommandArguments, '--output')
    Set-Content -LiteralPath $CommandArguments[$outputIndex + 1] -Value 'equivalent-descriptor' -NoNewline
    exit 0
}

throw "Unexpected fake Buf command: $($CommandArguments -join ' ')"
'@
}

function Invoke-BsrPublicationScenario {
    param([Parameter(Mandatory)][string]$Scenario)

    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "hm-bsr-publication-test-$([Guid]::NewGuid())"
    $originalPath = $env:Path
    $originalToken = $env:BUF_TOKEN
    try {
        New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
        $fakeScriptPath = Join-Path $temporaryDirectory 'fake-buf.ps1'
        $logPath = Join-Path $temporaryDirectory 'buf.log'
        $outputPath = Join-Path $temporaryDirectory 'github-output.txt'
        $resolveCountPath = Join-Path $temporaryDirectory 'resolve-count.txt'
        Set-Content -LiteralPath $fakeScriptPath -Value (Get-FakeBufScript) -NoNewline
        if ($IsWindows) {
            $fakeCommandPath = Join-Path $temporaryDirectory 'buf.cmd'
            Set-Content -LiteralPath $fakeCommandPath -Value '@pwsh -NoProfile -File "%~dp0fake-buf.ps1" %*' -NoNewline
        }
        else {
            $fakeCommandPath = Join-Path $temporaryDirectory 'buf'
            Set-Content -LiteralPath $fakeCommandPath -Value @'
#!/usr/bin/env sh
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec pwsh -NoProfile -File "$script_dir/fake-buf.ps1" "$@"
'@ -NoNewline
            & chmod +x $fakeCommandPath
            if ($LASTEXITCODE -ne 0) { throw 'The POSIX fake Buf command could not be made executable.' }
        }

        $sourceCommit = ('a' * 40) -join ''
        $env:HM_FAKE_BUF_SCENARIO = $Scenario
        $env:HM_FAKE_BUF_LOG = $logPath
        $env:HM_FAKE_BUF_RESOLVE_COUNT = $resolveCountPath
        $env:HM_FAKE_BUF_COMMIT_ID = '0123456789abcdef0123456789abcdef'
        $env:HM_FAKE_BUF_SOURCE_URL = Get-HmBsrSourceControlUrl -Commit $sourceCommit
        $env:BUF_TOKEN = 'test-token'
        $env:Path = "$temporaryDirectory$([System.IO.Path]::PathSeparator)$originalPath"
        $resolvedFakeCommandOutput = @(& pwsh -NoProfile -Command '$command = Get-Command buf -CommandType Application -ErrorAction Stop | Select-Object -First 1; [Console]::Out.Write($command.Source)')
        if ($LASTEXITCODE -ne 0 -or $resolvedFakeCommandOutput.Count -ne 1) { throw 'The fake Buf command does not take precedence on PATH.' }
        $resolvedFakeCommandPath = ([string]$resolvedFakeCommandOutput[0]).Trim()
        $canonicalFakeCommandPath = (Resolve-Path -LiteralPath $fakeCommandPath -ErrorAction Stop).ProviderPath
        $canonicalResolvedCommandPath = (Resolve-Path -LiteralPath $resolvedFakeCommandPath -ErrorAction Stop).ProviderPath
        $pathComparison = if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
        if (-not [string]::Equals($canonicalResolvedCommandPath, $canonicalFakeCommandPath, $pathComparison)) {
            throw 'The fake Buf command does not take precedence on PATH.'
        }

        & pwsh -NoProfile -File (Join-Path $PSScriptRoot '..\scripts\Publish-BsrRelease.ps1') -Tag 'v1.0.0-preview.1' -Commit $sourceCommit -GitHubOutputPath $outputPath *> $null
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{
            ExitCode = $exitCode
            Log = if (Test-Path -LiteralPath $logPath) { @(Get-Content -LiteralPath $logPath) } else { @() }
            Output = if (Test-Path -LiteralPath $outputPath) { Get-Content -LiteralPath $outputPath -Raw } else { '' }
        }
    }
    finally {
        $env:Path = $originalPath
        $env:BUF_TOKEN = $originalToken
        Remove-Item Env:HM_FAKE_BUF_SCENARIO -ErrorAction SilentlyContinue
        Remove-Item Env:HM_FAKE_BUF_LOG -ErrorAction SilentlyContinue
        Remove-Item Env:HM_FAKE_BUF_RESOLVE_COUNT -ErrorAction SilentlyContinue
        Remove-Item Env:HM_FAKE_BUF_COMMIT_ID -ErrorAction SilentlyContinue
        Remove-Item Env:HM_FAKE_BUF_SOURCE_URL -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
    }
}

$reference = 'buf.build/hdev-hm/logging:v1.0.0-preview.1'
$commitId = '0123456789abcdef0123456789abcdef'
$sourceControlUrl = Get-HmBsrSourceControlUrl -Commit '0123456789abcdef0123456789abcdef01234567'

$absent = Resolve-HmBsrCommitLookup -Reference $reference -ExitCode 1 -Output @("Failure: `"$reference`" does not exist")
Assert-Equal 'absent' $absent.State

$existing = Resolve-HmBsrCommitLookup -Reference $reference -ExitCode 0 -Output @("{`"commit`":`"$commitId`"}")
Assert-Equal 'existing' $existing.State
Assert-Equal $commitId $existing.CommitId

Assert-Throws { Resolve-HmBsrCommitLookup -Reference $reference -ExitCode 1 -Output @('Failure: unauthorized') }
Assert-Throws { Resolve-HmBsrCommitLookup -Reference $reference -ExitCode 0 -Output @('{"commit":"invalid"}') }

$matchingInfo = "{`"commit`":`"$commitId`",`"source_control_url`":`"$sourceControlUrl`"}"
Assert-HmBsrCommitSourceIdentity -CommitId $commitId -ExpectedSourceControlUrl $sourceControlUrl -ExitCode 0 -Output @($matchingInfo)
Assert-Throws { Assert-HmBsrCommitSourceIdentity -CommitId $commitId -ExpectedSourceControlUrl $sourceControlUrl -ExitCode 0 -Output @("{`"commit`":`"$commitId`"}") }
Assert-Throws { Assert-HmBsrCommitSourceIdentity -CommitId $commitId -ExpectedSourceControlUrl $sourceControlUrl -ExitCode 0 -Output @("{`"commit`":`"$commitId`",`"source_control_url`":`"https://example.invalid/other`"}") }

$publicationScript = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\scripts\Publish-BsrRelease.ps1') -Raw
Assert-Equal $true ($publicationScript.IndexOf('Resolve-BsrReleaseCommit -Reference $reference') -lt $publicationScript.IndexOf('& buf push'))
Assert-Equal $true ($publicationScript -match 'if \(\$lookup\.State -eq ''absent''\)')
Assert-Equal $true ($publicationScript -match 'Assert-BsrReleaseCommit')
Assert-Equal $true ($publicationScript -match 'bsr_state=\$state')
Assert-Equal $true ($publicationScript -match 'bsr_commit_id=\$\(\$lookup\.CommitId\)')

$existingResult = Invoke-BsrPublicationScenario -Scenario 'existing'
Assert-Equal 0 $existingResult.ExitCode
Assert-Equal 0 (@($existingResult.Log | Where-Object { $_.StartsWith('push|', [System.StringComparison]::Ordinal) }).Count)
Assert-True ($existingResult.Output -match 'bsr_state=already_verified') 'Existing matching releases must be already verified.'
Assert-True ($existingResult.Output -match "bsr_commit_id=$commitId") 'Existing matching releases must recover the immutable commit ID.'

$conflictingResult = Invoke-BsrPublicationScenario -Scenario 'conflicting-source'
Assert-True ($conflictingResult.ExitCode -ne 0) 'A conflicting existing source identity must fail.'
Assert-Equal 0 (@($conflictingResult.Log | Where-Object { $_.StartsWith('push|', [System.StringComparison]::Ordinal) }).Count)
Assert-True ($conflictingResult.Output -notmatch 'bsr_state=') 'A conflicting existing release must not emit a successful state.'

$absentResult = Invoke-BsrPublicationScenario -Scenario 'absent'
Assert-Equal 0 $absentResult.ExitCode
Assert-Equal 1 (@($absentResult.Log | Where-Object { $_.StartsWith('push|', [System.StringComparison]::Ordinal) }).Count)
Assert-True ((Get-LoggedCommandIndex -Log $absentResult.Log -Prefix 'push|') -lt (Get-LoggedCommandIndex -Log $absentResult.Log -Prefix 'registry|module|commit|info|')) 'New releases must verify commit information after publication.'
Assert-True ($absentResult.Output -match 'bsr_state=published') 'New releases must be published only after verification succeeds.'
Assert-True ($absentResult.Output -match "bsr_commit_id=$commitId") 'New releases must emit the resolved immutable commit ID.'

$lookupFailureResult = Invoke-BsrPublicationScenario -Scenario 'lookup-failure'
Assert-True ($lookupFailureResult.ExitCode -ne 0) 'Non-not-found BSR lookup failures must fail.'
Assert-Equal 0 (@($lookupFailureResult.Log | Where-Object { $_.StartsWith('push|', [System.StringComparison]::Ordinal) }).Count)

Write-Output 'BSR publication tests passed.'
