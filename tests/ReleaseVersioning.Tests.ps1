[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '..\scripts\ReleaseVersioning.psm1') -Force

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        $Expected,

        [Parameter(Mandatory)]
        $Actual,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', received '$Actual'."
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [Parameter(Mandatory)]
        [string]$Message
    )

    try {
        & $Action
    }
    catch {
        return
    }

    throw "$Message Expected an exception."
}

foreach ($tag in @(
    'v0.0.0',
    'v1.0.0',
    'v1.0.0-alpha',
    'v1.0.0-alpha.1',
    'v1.0.0-preview.1',
    'v1.2.3-rc.2')) {
    $release = Resolve-HmReleaseTag -Tag $tag
    Assert-Equal -Expected $tag -Actual $release.Tag -Message "Tag '$tag' was not retained."
    Assert-Equal -Expected $tag.Substring(1) -Actual $release.ReleaseVersion -Message "Tag '$tag' was not derived correctly."
}

foreach ($tag in @(
    '1.0.0',
    'v1',
    'v1.0',
    'v1.0.0.0',
    'v01.0.0',
    'v1.01.0',
    'v1.0.01',
    'v1.0.0-',
    'v1.0.0-alpha..1',
    'v1.0.0-alpha_',
    'v1.0.0-01.alpha',
    'v1.0.0-preview.01',
    'v1.0.0+build.1',
    'v1.0.0-preview.1+build.45')) {
    Assert-Throws -Action { Resolve-HmReleaseTag -Tag $tag } -Message "Tag '$tag' was accepted."
}

foreach ($releaseVersion in @('0.0.0', '1.0.0-alpha.1')) {
    $release = Assert-HmReleaseVersion -ReleaseVersion $releaseVersion
    Assert-Equal -Expected $releaseVersion -Actual $release.ReleaseVersion -Message "ReleaseVersion '$releaseVersion' was not accepted."
}

$temporaryRepository = Join-Path ([System.IO.Path]::GetTempPath()) "hm-release-versioning-$([Guid]::NewGuid())"
try {
    New-Item -ItemType Directory -Path $temporaryRepository | Out-Null

    & git -C $temporaryRepository init --initial-branch=main *> $null
    & git -C $temporaryRepository config user.email 'release-versioning@example.invalid'
    & git -C $temporaryRepository config user.name 'Release Versioning Test'

    Set-Content -LiteralPath (Join-Path $temporaryRepository 'tracked.txt') -Value 'ancestor'
    & git -C $temporaryRepository add tracked.txt
    & git -C $temporaryRepository commit -m 'ancestor commit' *> $null
    $ancestorCommit = (& git -C $temporaryRepository rev-parse HEAD).Trim()
    & git -C $temporaryRepository tag v1.0.0-preview.1

    Set-Content -LiteralPath (Join-Path $temporaryRepository 'tracked.txt') -Value 'main head'
    & git -C $temporaryRepository commit -am 'main head commit' *> $null
    $mainHeadCommit = (& git -C $temporaryRepository rev-parse HEAD).Trim()

    Assert-HmCommitInMainHistory -RepositoryPath $temporaryRepository -Commit $mainHeadCommit -MainBranch main
    Assert-HmCommitInMainHistory -RepositoryPath $temporaryRepository -Commit $ancestorCommit -MainBranch main
    $ancestorContext = Resolve-HmReleaseContext -RepositoryPath $temporaryRepository -Tag v1.0.0-preview.1 -MainBranch main
    Assert-Equal -Expected $ancestorCommit -Actual $ancestorContext.Commit -Message 'The tagged main ancestor was not retained.'

    & git -C $temporaryRepository checkout -b outside-main $ancestorCommit *> $null
    Set-Content -LiteralPath (Join-Path $temporaryRepository 'outside.txt') -Value 'outside main history'
    & git -C $temporaryRepository add outside.txt
    & git -C $temporaryRepository commit -m 'outside main history' *> $null
    $outsideCommit = (& git -C $temporaryRepository rev-parse HEAD).Trim()
    & git -C $temporaryRepository tag v1.0.1

    Assert-Throws -Action { Assert-HmCommitInMainHistory -RepositoryPath $temporaryRepository -Commit $outsideCommit -MainBranch main } -Message 'A commit outside main history was accepted.'
    Assert-Throws -Action { Resolve-HmReleaseContext -RepositoryPath $temporaryRepository -Tag v1.0.1 -MainBranch main } -Message 'A tag outside main history was accepted.'
    Assert-Throws -Action { Assert-HmCheckedOutCommit -RepositoryPath $temporaryRepository -Commit $mainHeadCommit } -Message 'A checked-out commit different from the expected release commit was accepted.'
}
finally {
    if (Test-Path $temporaryRepository) {
        Remove-Item -LiteralPath $temporaryRepository -Recurse -Force
    }
}

Write-Output 'Release versioning tests passed.'
