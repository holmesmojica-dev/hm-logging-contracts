# Hm.Logging.Contracts

Language-neutral Protocol Buffers and gRPC contracts for the HM Logging ecosystem.

This repository contains the initial `hm.logging.contracts.v1` schema and
generates its .NET protobuf and gRPC contract types.

The v1 protocol includes structured `LogEntry` and `LogContext` messages,
typed scalar metadata, Log Levels, and the `LoggingService` Flow-operation
contract (`CreateFlow`, `CloseFlow`, `PushScope`, `PopScope`, and `Log`).

The repository contains Contracts only. It does not implement the Logging
Service runtime, Flow state, providers, persistence, or Hm.Logging Core
behavior.

HM-owned schemas are under `proto/hm/logging/contracts/v1/`. Buf configuration
and the dependency lock file govern protobuf formatting, linting, building,
and future compatibility validation.

## Validation

Enable the repository-managed pre-commit hook after cloning:

```powershell
pwsh -File scripts/install-hooks.ps1
```

The hook runs formatting verification, a Release build and test run, and Buf
format, lint, and build checks. Pull requests targeting `main` run the same
validations in GitHub Actions; CI is the authoritative validation gate.

Authoritative CI also runs a NuGet dependency vulnerability audit, generates
Sonar-supported .NET coverage XML for handwritten code, performs SonarQube Cloud analysis,
and blocks integration when the Sonar Quality Gate fails. Pull requests also
run GitHub Dependency Review, blocking newly introduced moderate, high, or
critical vulnerabilities. Sonar and Dependency Review are CI-only; they are
not part of the local pre-commit hook.

A release is eligible only when the authoritative Sonar Quality Gate has
successfully verified the exact release commit. Future publication automation
will enforce that rule.
