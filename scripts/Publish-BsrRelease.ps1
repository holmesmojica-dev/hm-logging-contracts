[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Tag,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$GitHubOutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'BsrValidation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'BsrPublication.psm1') -Force

function Invoke-BufJsonCommand {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = @(& buf @Arguments 2>&1 | ForEach-Object { $_.ToString() })
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output }
}

function Resolve-BsrReleaseCommit {
    param([Parameter(Mandatory)][string]$Reference)

    $result = Invoke-BufJsonCommand -Arguments @('registry', 'module', 'commit', 'resolve', $Reference, '--format', 'json', '--timeout', '60s')
    return Resolve-HmBsrCommitLookup -Reference $Reference -ExitCode $result.ExitCode -Output $result.Output
}

function Assert-BsrReleaseCommit {
    param(
        [Parameter(Mandatory)][string]$ModuleName,
        [Parameter(Mandatory)][string]$CommitId,
        [Parameter(Mandatory)][string]$ExpectedSourceControlUrl
    )

    $info = Invoke-BufJsonCommand -Arguments @('registry', 'module', 'commit', 'info', "${ModuleName}:$CommitId", '--format', 'json', '--timeout', '60s')
    Assert-HmBsrCommitSourceIdentity -CommitId $CommitId -ExpectedSourceControlUrl $ExpectedSourceControlUrl -ExitCode $info.ExitCode -Output $info.Output

    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "hm-bsr-release-$([Guid]::NewGuid())"
    try {
        New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null
        $localDescriptor = Join-Path $temporaryDirectory 'local.binpb'
        $remoteDescriptor = Join-Path $temporaryDirectory 'remote.binpb'
        & buf build . --as-file-descriptor-set --output $localDescriptor
        if ($LASTEXITCODE -ne 0) { throw 'Buf could not build the validated local descriptor set.' }
        & buf build "${ModuleName}:$CommitId" --as-file-descriptor-set --output $remoteDescriptor
        if ($LASTEXITCODE -ne 0) { throw 'Buf could not build the remote BSR descriptor set.' }
        if ((Get-FileHash $localDescriptor -Algorithm SHA256).Hash -ne (Get-FileHash $remoteDescriptor -Algorithm SHA256).Hash) { throw 'The immutable BSR commit is not semantically equivalent to the validated local descriptor set.' }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDirectory) { Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force }
    }
}

if ([string]::IsNullOrWhiteSpace($env:BUF_TOKEN)) { throw 'BUF_TOKEN must be supplied for BSR publication.' }
$moduleName = Get-HmBsrModuleName
$reference = "${moduleName}:$Tag"
$sourceUrl = Get-HmBsrSourceControlUrl -Commit $Commit
$lookup = Resolve-BsrReleaseCommit -Reference $reference

if ($lookup.State -eq 'absent') {
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        & buf push --label $Tag --source-control-url $sourceUrl --timeout 60s
        if ($LASTEXITCODE -eq 0) { break }
        if ($attempt -eq 2) { throw 'BSR publication failed after two attempts.' }
        Start-Sleep -Seconds 10
    }

    $lookup = Resolve-BsrReleaseCommit -Reference $reference
    if ($lookup.State -ne 'existing') { throw "BSR publication did not create release label '$Tag'." }
    $state = 'published'
}
else {
    $state = 'already_verified'
}

Assert-BsrReleaseCommit -ModuleName $moduleName -CommitId $lookup.CommitId -ExpectedSourceControlUrl $sourceUrl
@("release_version=$($Tag.Substring(1))", "source_commit=$Commit", "bsr_state=$state", "bsr_commit_id=$($lookup.CommitId)") | Add-Content -LiteralPath $GitHubOutputPath
