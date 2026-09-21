# Hm.Logging.Contracts

`Hm.Logging.Contracts` defines the language-neutral Protocol Buffers and gRPC
contract for distributed HM Logging. It represents the HM Logging domain and
the distributed Logging Flow architecture; it does not implement logging
behavior.

The .NET NuGet package, `HDev.Hm.Logging.Contracts`, is the official .NET
distribution of the Contracts v1 schemas. It contains generated protobuf and
gRPC types for `net10.0`, together with the HM-owned canonical schemas.

## Scope

Contracts defines the data and operations that can cross a process boundary:

- structured `LogEntry` and `LogContext` messages;
- ordered `LogLevel` values;
- scalar, language-neutral `MetadataValue` representations;
- the distributed Logging Flow protocol; and
- the `LoggingService` gRPC service definition.

It does not implement a gRPC server, Flow state, Flow expiration, context
normalization, persistence, providers, or `Hm.Logging` Core behavior. A
service or other consumer owns runtime validation, Flow lifecycle management,
and mapping a valid contract request into its logging implementation.

## Installation and target framework

The package targets .NET 10:

```bash
dotnet add package HDev.Hm.Logging.Contracts --prerelease
```

Use the generated `Hm.Logging.Contracts` types with a gRPC transport and
service implementation chosen by your application. This package supplies the
contract; it does not configure a channel or host a service.

## Protocol identity

The canonical protobuf package is:

```text
hm.logging.contracts.v1
```

Its gRPC service is `LoggingService`, with five unary operations:

| RPC | Purpose | Important behavior |
| --- | --- | --- |
| `CreateFlow` | Creates a new empty Flow. | Returns a new opaque `flow_id`; it is not idempotent. |
| `CloseFlow` | Explicitly ends a Flow. | Idempotent by postcondition; `ALREADY_CLOSED` is a valid `OK` outcome. |
| `PushScope` | Adds a `LogContext` layer. | Does not create a missing Flow; repeating the top normalized context returns `ALREADY_EXISTS`. |
| `PopScope` | Removes the top context layer. | LIFO; the guarded `expected_context` form is retry-safe, while an unconditional pop is not. |
| `Log` | Submits a `LogEntry`. | A Flow is optional. A valid but inactive Flow accepts the log without Flow context. Log is not idempotent. |

The generated .NET API includes `LoggingService.LoggingServiceClient` and
`LoggingService.LoggingServiceBase`. They are generated contract types, not a
service implementation.

## Logging Flows

A Logging Flow is server-managed remote contextual state identified by an
opaque FlowId. It is not a trace ID, correlation ID, or business identifier.
Its lifecycle is explicit:

```text
CreateFlow -> PushScope -> Log -> PopScope -> CloseFlow
```

`PushScope` adds one context layer and `PopScope` removes only the most recent
layer. An empty stack remains an active Flow; only `CloseFlow` or
Service-owned expiration ends the lifecycle. An independent `Log` may omit a
Flow ID entirely.

Clients are responsible for the logical ordering of concurrent operations on
the same Flow. A service is responsible for preserving Flow integrity and
serializing its state mutations.

## Log entries and field presence

`LogEntry` contains a required semantic `message`, an optionally present
`level`, an optionally supplied `timestamp`, optional source/trace/correlation
and exception text, and a metadata map.

Protobuf presence is intentional:

- `level` uses `optional` because `TRACE` is the valid numeric value `0` and
  must remain distinguishable from omission.
- optional strings preserve the distinction between omission and an explicit
  value.
- message-valued fields, including `timestamp`, have protobuf message
  presence.
- Contracts preserves omitted `level` and `timestamp`; it does not generate a
  logging level, timestamp, or trace ID.

The receiving implementation performs semantic validation and mapping. For
example, a Service rejects an empty or whitespace-only message, and it must
apply the HM Logging domain requirements before writing an event.

The following construction example uses the actual generated .NET types:

```csharp
using Google.Protobuf.WellKnownTypes;
using Hm.Logging.Contracts;

var entry = new LogEntry
{
    Message = "Order submitted.",
    Level = LogLevel.LogLevelInformation,
    Timestamp = Timestamp.FromDateTime(DateTime.UtcNow),
    Source = "checkout"
};

entry.Metadata.Add("order.id", new MetadataValue
{
    StringValue = "ORD-1042"
});

var request = new LogRequest { Entry = entry };

// Generated presence properties distinguish omission from a supplied value.
bool hasLevel = entry.HasLevel;
bool isFlowBound = request.HasFlowId;
```

Setting `request.FlowId` makes the request Flow-bound; leaving it unset creates
an independent log request.

## Metadata values

`MetadataValue` is a protobuf `oneof` with these scalar semantic categories:

- text (`string_value`);
- boolean;
- signed and unsigned 64-bit integers;
- single- and double-precision floating point;
- decimal;
- date/time; and
- duration.

Metadata is intentionally not an object container. Bytes, arbitrary objects,
arrays, nested collections, and object graphs are not Contracts v1 metadata
values. Adapt complex values before logging: flatten useful properties into
scalar metadata entries, or serialize the value to text such as JSON. The
contract does not reconstruct the originating object model.

An unset `MetadataValue` oneof represents no retained value. Semantic mapping
can discard such entries and other normalizable empty metadata; it must not
silently reinterpret explicitly malformed typed values.

### Date/time, UTC offsets, and duration

`LogEntry.timestamp` and `DateTimeValue.timestamp` use
`google.protobuf.Timestamp` and represent absolute instants. A producer must
resolve a local or ambiguous date/time before transmission; neither Contracts
nor a receiver infers a time zone.

`DateTimeValue.utc_offset` is an optional `google.protobuf.Duration`. When
present, it preserves the offset of the producer's original representation.
It does not change the absolute instant and is not a time-zone identifier.
Duration metadata uses `google.protobuf.Duration` directly.

### Decimal

Decimal metadata uses the canonical Google Common Protos
`google.type.Decimal` representation. Contracts does not replace it with a
floating-point value or an HM-specific decimal type. Parsing, canonicalization,
range checking, and lossless conversion to a native decimal type belong to the
consumer. A Service must reject malformed, out-of-range, or lossy decimal
input before writing a log or mutating Flow state.

## Statuses, semantic results, and retries

gRPC status answers whether an operation executed validly. Typed response
result enums answer which valid outcome occurred. For example, valid no-op
outcomes such as `CLOSE_FLOW_RESULT_ALREADY_CLOSED`,
`PUSH_SCOPE_RESULT_ALREADY_EXISTS`, `POP_SCOPE_RESULT_NO_SCOPES`, and
`LOG_RESULT_ACCEPTED_WITHOUT_FLOW` use gRPC `OK`. Invalid or failed requests
use gRPC statuses such as `INVALID_ARGUMENT`, `NOT_FOUND`,
`FAILED_PRECONDITION`, or `INTERNAL`.

Result-enum zero values are defensive `UNSPECIFIED` values, not functional
outcomes. This convention does not apply to `LogLevel`: `TRACE` is valid at
numeric value zero.

Retry behavior is part of the public contract:

- `CreateFlow` and `Log` are not idempotent; retrying after a lost response may
  create another Flow or duplicate a log entry.
- `CloseFlow` is idempotent by postcondition.
- `PushScope` is retry-safe because an equivalent normalized top context is not
  added twice.
- `PopScope` is retry-safe only when `expected_context` is supplied.

## Interoperability and distribution

The `.proto` files are the language-neutral source of truth. Consumers in
other languages can use the canonical schemas with their own protobuf/gRPC
toolchains and explicitly control code generation and integration.

The NuGet package is a .NET distribution mechanism. It includes generated
.NET types and the HM-owned schemas at:

```text
content/protos/hm/logging/contracts/v1/
```

Those schema files are package content for discovery, inspection,
interoperability, and consumer-controlled generation. The package does not
include `build` or `buildTransitive` integration that automatically injects or
compiles them in consumer projects. Google protobuf schemas, including
`google.type.Decimal`, remain external dependencies and are not repackaged as
HM-owned content.

The Buf Schema Registry is the intended language-neutral distribution channel
when the module is published. Contracts v1 is not currently published to BSR;
Git remains the canonical source for HM-owned schemas.

## Compatibility and versioning

The protobuf API identity is `hm.logging.contracts.v1`; preview maturity does
not change that identity. The NuGet package major version aligns with the
protobuf major version, so Contracts v1 is distributed as package `1.x.x`.

The first public preview establishes the compatibility baseline for v1.
Existing field numbers and enum numeric values must not be reused or
renumbered within v1. Backward-compatible additions may evolve within v1; a
breaking wire change requires a new protobuf API version, such as v2, unless an
architecturally approved exception exists.

Package-manager SemVer and protobuf API versioning are related but distinct.
Release builds derive package identity from the release SemVer tag, retain the
v1 assembly identity `1.0.0.0`, and provide portable symbols and Source
Link-compatible source mapping.

## Quality and validation

Repository validation includes formatting, a zero-warning Release build,
automated tests, and Buf formatting, lint, and build checks:

```powershell
pwsh -File scripts/validate.ps1
```

CI additionally performs dependency auditing, coverage collection for
handwritten code, SonarQube Cloud analysis with a blocking Quality Gate, and
Pull Request dependency review. Generated protobuf and gRPC code is excluded
from source-quality metrics.

## Contributing

Read the HM Logging domain and Contracts architecture before proposing a
contract change. Preserve protobuf v1 compatibility and run the repository
validation before opening a Pull Request. Contracts changes must remain
language-neutral and must not introduce Service runtime, provider, persistence,
or Core behavior.

## License

Hm.Logging.Contracts is licensed under the [MIT License](LICENSE).
