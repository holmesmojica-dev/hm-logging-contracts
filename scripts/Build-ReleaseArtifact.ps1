[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ReleaseVersion,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ReleaseVersioning.psm1') -Force

$repositoryPath = (& git rev-parse --show-toplevel).Trim()
Assert-HmReleaseVersion -ReleaseVersion $ReleaseVersion | Out-Null
Assert-HmCheckedOutCommit -RepositoryPath $repositoryPath -Commit $Commit
$outputPath = Join-Path $repositoryPath $OutputDirectory

& dotnet restore Hm.Logging.Contracts.slnx
if ($LASTEXITCODE -ne 0) { throw 'Release artifact restore failed.' }

& dotnet pack src/Hm.Logging.Contracts/Hm.Logging.Contracts.csproj --configuration Release --no-restore --output $outputPath "-p:ReleaseVersion=$ReleaseVersion" "-p:RepositoryCommit=$Commit" "-p:SourceRevisionId=$Commit" '-p:ContinuousIntegrationBuild=true'
if ($LASTEXITCODE -ne 0) { throw 'Release artifact packaging failed.' }

& (Join-Path $PSScriptRoot 'Validate-ReleaseArtifact.ps1') -PackageDirectory $outputPath -ReleaseVersion $ReleaseVersion -Commit $Commit
