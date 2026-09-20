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
