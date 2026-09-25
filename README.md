# Hm.Logging.Contracts

[![NuGet](https://img.shields.io/nuget/vpre/HDev.Hm.Logging.Contracts?label=nuget)](https://www.nuget.org/packages/HDev.Hm.Logging.Contracts)
[![BSR](https://img.shields.io/badge/BSR-hdev--hm%2Flogging-blue)](https://buf.build/hdev-hm/logging)
[![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=holmesmojica-dev_hm-logging-contracts&metric=alert_status)](https://sonarcloud.io/summary/new_code?id=holmesmojica-dev_hm-logging-contracts)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![.NET](https://img.shields.io/badge/.NET-10-512BD4)](https://dotnet.microsoft.com/)

`Hm.Logging.Contracts` defines the language-neutral Protocol Buffers and gRPC
contract for distributed HM Logging. It represents the HM Logging domain and
the distributed Logging Flow architecture; it does not implement logging
behavior.

The .NET NuGet package, `HDev.Hm.Logging.Contracts`, is the official .NET
distribution of the Contracts v1 schemas. It contains generated protobuf and
gRPC types for `net10.0`, together with the HM-owned canonical schemas.

Use this package when a .NET application needs to send structured events to a
compatible HM Logging gRPC endpoint or implement that endpoint's contract.
Start with independent logging; use a Logging Flow when multiple calls need
shared contextual defaults or nested scopes.

This README is the integration guide. The
[BSR API reference](https://buf.build/hdev-hm/logging) documents every message,
field, RPC and result, including the complete validation and retry semantics.

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

You need a compatible endpoint and a configured gRPC channel, including the
address, credentials and transport settings appropriate to your deployment.
Construct the generated client using the channel's `Grpc.Core.CallInvoker`:

```csharp
using Hm.Logging.Contracts;

// callInvoker is supplied by your application's configured gRPC transport.
var client = new LoggingService.LoggingServiceClient(callInvoker);
```

The examples below use this `client`. They do not assume a public HM Logging
endpoint or install a transport as part of the Contracts package.

## Concepts and choosing values

| Concept | Use it for |
| --- | --- |
| `LogEntry` | One event: message, severity, event time and event-specific facts. |
| `LogLevel` | Severity, independent of whether a Flow is used. |
| `LogContext` | Shared source, trace, correlation and metadata defaults across events. |
| Metadata | Named scalar facts for filtering and diagnostics, such as `order.id`. |
| Logging Flow | Remote contextual lifetime identified by an opaque ID returned by `CreateFlow`. |

Choose levels according to the event:

| Level | Intended use |
| --- | --- |
| Trace | Detailed diagnostics about execution behavior. |
| Debug | Developer-focused troubleshooting information. |
| Information | Normal application activity, such as an order being submitted. |
| Warning | A potential problem or unexpected situation. |
| Error | A failure during execution. |
| Critical | A severe failure requiring immediate attention. |

`Source` identifies a logical application, service, component or module, for
example `checkout-service`. `TraceId` connects an event to a technical execution
trace; `CorrelationId` links related requests, services or business operations.
Supply known identifiers or inherit them from context. Neither is a Flow ID,
and Contracts does not generate them.

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

The innermost context overrides inherited context; explicit `LogEntry` values
override context. Metadata is merged by key with the same precedence. For
example, a context's `Source = "checkout-service"` and `tenant.id` apply to
entries that do not supply those values. An entry can override either without
changing the context. An empty normalized context cannot be pushed.

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

An empty or whitespace-only message is invalid and causes `Log` to return
`INVALID_ARGUMENT`. Set level and event time explicitly when their values
matter; omission does not instruct Contracts to generate a replacement.

### Send an independent log

Use `Log` directly when you do not need shared context across calls. The
following example constructs an event and sends it with the generated client:

```csharp
using Google.Protobuf.WellKnownTypes;
using Hm.Logging.Contracts;

var entry = new LogEntry
{
    Message = "Order submitted.",
    Level = LogLevel.Information,
    Timestamp = Timestamp.FromDateTime(DateTime.UtcNow),
    Source = "checkout-service"
};

entry.Metadata.Add("order.id", new MetadataValue
{
    StringValue = "ORD-1042"
});

var request = new LogRequest { Entry = entry };

// Generated presence properties distinguish omission from a supplied value.
bool hasLevel = entry.HasLevel;
bool isFlowBound = request.HasFlowId;

LogResponse response = await client.LogAsync(request);
Console.WriteLine(response.Result); // Accepted for a successful independent log.
```

Setting `request.FlowId` makes the request Flow-bound; leaving it unset creates
an independent log request.

Leave `FlowId` unset rather than assigning an empty string: a present empty or
whitespace-only identifier is invalid. `HasLevel` is true even when Trace is
explicitly selected; reading the numeric enum alone cannot establish presence.

### Send logs within a Flow

This example owns a newly created Flow and makes calls sequentially. It shares
source and correlation information without repeating them on each entry:

```csharp
var flow = await client.CreateFlowAsync(new CreateFlowRequest());
var context = new LogContext
{
    Source = "checkout-service",
    CorrelationId = "order-1042"
};
context.Metadata.Add("tenant.id", new MetadataValue { StringValue = "tenant-a" });

try
{
    var pushed = await client.PushScopeAsync(new PushScopeRequest
    {
        FlowId = flow.FlowId,
        Context = context
    });
    if (pushed.Result is not (PushScopeResult.Added or PushScopeResult.AlreadyExists))
        throw new InvalidOperationException("Unexpected PushScope result.");

    var logged = await client.LogAsync(new LogRequest
    {
        FlowId = flow.FlowId,
        Entry = new LogEntry
        {
            Message = "Order submitted.",
            Level = LogLevel.Information,
            Timestamp = Timestamp.FromDateTime(DateTime.UtcNow)
        }
    });
    // AcceptedWithoutFlow means the event was accepted but context was unavailable.
    // Do not resubmit an accepted event merely to recover its missing context.
    Console.WriteLine(logged.Result);

    if (pushed.Result == PushScopeResult.Added)
    {
        var popped = await client.PopScopeAsync(new PopScopeRequest
        {
            FlowId = flow.FlowId,
            ExpectedContext = context
        });
        Console.WriteLine(popped.Result); // Inspect no-op outcomes as well as Removed.
    }
}
finally
{
    var closed = await client.CloseFlowAsync(new CloseFlowRequest { FlowId = flow.FlowId });
    Console.WriteLine(closed.Result); // Closed and AlreadyClosed both satisfy closure.
}
```

The `using` directives from the independent example also apply here. In an
application, handle RPC and cleanup failures explicitly, and configure deadlines
and cancellation for its needs. The example does not automatically retry calls.

Scopes are LIFO. Only an `Added` push introduces another layer to pop;
`AlreadyExists` means an equivalent context was already on top. A guarded pop
compares the normalized expected context with the current top, not a unique
scope ID. A mismatch removes nothing; an empty active Flow returns `NoScopes`.
Coordinate concurrent calls and retries on a shared Flow so their intended
ordering is preserved.

After closure or expiration, scope operations return `NOT_FOUND`. Logging with
a valid but inactive/nonexistent Flow ID still accepts a valid event without
Flow context and reports `AcceptedWithoutFlow`. This fallback does not bypass
event validation, and an empty active Flow remains a valid logging target.

## Metadata values

`MetadataValue` is a protobuf `oneof` with these scalar semantic categories:

- text (`string_value`);
- boolean;
- signed and unsigned 64-bit integers;
- single- and double-precision floating point;
- decimal;
- date/time; and
- duration.

Use meaningful application keys, for example:

```csharp
entry.Metadata.Add("retry.count", new MetadataValue { SignedIntegerValue = 2 });
entry.Metadata.Add("cache.hit", new MetadataValue { BooleanValue = false });
```

Select one value branch per entry. Explicit `false` and zero remain supplied
values. UUID/GUID values, characters and enum names can use `StringValue`;
Contracts does not infer their originating runtime type. Use signed versus
unsigned integers and single versus double precision to preserve the category
and range of the original value.

The following keys are **reserved, case-insensitively**: `Message`, `Level`,
`Timestamp`, `Source`, `TraceId`, `CorrelationId`, `Exception`, and `Metadata`.
Use the dedicated fields instead of redefining them in metadata. The same
rules apply to `LogContext.Metadata`; explicit entry values win key collisions.

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
floating-point value or an HM-specific decimal type. The value must satisfy
the Google decimal representation rules. Separately, conversion to a native
decimal type must preserve its value: supported range and precision depend on
the target language/runtime. A valid wire decimal is not necessarily
representable by every native decimal type.

## Statuses, semantic results, and retries

gRPC status answers whether an operation executed validly. Typed response
result enums answer which valid outcome occurred. For example, valid no-op
outcomes such as `CLOSE_FLOW_RESULT_ALREADY_CLOSED`,
`PUSH_SCOPE_RESULT_ALREADY_EXISTS`, `POP_SCOPE_RESULT_NO_SCOPES`, and
`LOG_RESULT_ACCEPTED_WITHOUT_FLOW` use gRPC `OK`. Invalid or failed requests
use gRPC statuses such as `INVALID_ARGUMENT`, `NOT_FOUND`,
`FAILED_PRECONDITION`, or `INTERNAL`.

With the generated C# client, a non-OK call raises `Grpc.Core.RpcException`;
inspect its `StatusCode`. After a successful call, inspect `response.Result`
instead of parsing `response.Message`. For example, a guarded pop may return
`ContextMismatch` on gRPC OK without removing a scope. A lost response or
transport failure does not establish whether the operation took effect.

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

The scope retry rules depend on the current top context, not request history.
Order other operations on the same Flow during retries. Do not enable blanket
automatic retries for `CreateFlow` or `Log` under an assumption of deduplication.

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

The Buf Schema Registry distributes and provides language-neutral discovery for
the HM-owned protobuf schemas through [buf.build/hdev-hm/logging](https://buf.build/hdev-hm/logging).
Use BSR as the exhaustive schema/API reference and discover the imports needed
by your language's tooling there. Git remains
the authoritative source and history for the schemas.

## Compatibility and versioning

The protobuf API identity is `hm.logging.contracts.v1`; preview maturity does
not change that identity. The NuGet package major version aligns with the
protobuf major version, so Contracts v1 is distributed as package `1.x.x`.

The first public preview establishes the compatibility baseline for v1.
Existing field numbers and enum numeric values must not be reused or
renumbered within v1. Backward-compatible additions may evolve within v1; a
breaking wire change requires a new protobuf API version, such as v2. The
published v1 baseline does not allow breaking-change overrides.

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
