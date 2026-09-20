using Google.Protobuf.WellKnownTypes;
using Xunit;
using GoogleDecimal = Google.Type.Decimal;

namespace Hm.Logging.Contracts.Tests;

public sealed class ContractSchemaTests
{
    [Fact]
    public void GeneratedTypesExposeTheApprovedPackageAndServiceIdentity()
    {
        Assert.Equal("hm.logging.contracts.v1.LogEntry", LogEntry.Descriptor.FullName);
        Assert.Equal("hm.logging.contracts.v1.LoggingService", LoggingService.Descriptor.FullName);
        Assert.Equal(5, LoggingService.Descriptor.Methods.Count);
    }

    [Fact]
    public void LogEntryPreservesOptionalLevelPresenceIncludingTrace()
    {
        LogEntry entry = new();

        Assert.False(entry.HasLevel);
        Assert.Equal(LogLevel.Trace, entry.Level);

        entry.Level = LogLevel.Trace;

        Assert.True(entry.HasLevel);
        Assert.Equal(LogLevel.Trace, entry.Level);
    }

    [Fact]
    public void LogEntryPreservesOptionalScalarPresenceAndTimestampAbsence()
    {
        LogEntry entry = new();

        Assert.Null(entry.Timestamp);
        Assert.False(entry.HasSource);
        Assert.False(entry.HasTraceId);
        Assert.False(entry.HasCorrelationId);
        Assert.False(entry.HasException);

        entry.Source = string.Empty;
        entry.TraceId = "trace";
        entry.CorrelationId = "correlation";
        entry.Exception = "diagnostic";

        Assert.True(entry.HasSource);
        Assert.True(entry.HasTraceId);
        Assert.True(entry.HasCorrelationId);
        Assert.True(entry.HasException);
    }

    [Fact]
    public void MetadataValueUsesOneofSemantics()
    {
        MetadataValue value = new()
        {
            StringValue = "text"
        };

        Assert.Equal(MetadataValue.ValueOneofCase.StringValue, value.ValueCase);

        value.BooleanValue = true;

        Assert.Equal(MetadataValue.ValueOneofCase.BooleanValue, value.ValueCase);
        Assert.True(value.BooleanValue);
        Assert.Equal(string.Empty, value.StringValue);
    }

    [Fact]
    public void MetadataValuePreservesSignedAndUnsignedIntegerBoundaries()
    {
        MetadataValue signed = new()
        {
            SignedIntegerValue = long.MinValue
        };
        MetadataValue unsigned = new()
        {
            UnsignedIntegerValue = ulong.MaxValue
        };

        Assert.Equal(MetadataValue.ValueOneofCase.SignedIntegerValue, signed.ValueCase);
        Assert.Equal(long.MinValue, signed.SignedIntegerValue);
        Assert.Equal(MetadataValue.ValueOneofCase.UnsignedIntegerValue, unsigned.ValueCase);
        Assert.Equal(ulong.MaxValue, unsigned.UnsignedIntegerValue);
    }

    [Fact]
    public void MetadataValuePreservesFloatAndDoubleRepresentations()
    {
        MetadataValue single = new()
        {
            FloatValue = float.NaN
        };
        MetadataValue doublePrecision = new()
        {
            DoubleValue = double.PositiveInfinity
        };

        Assert.Equal(MetadataValue.ValueOneofCase.FloatValue, single.ValueCase);
        Assert.True(float.IsNaN(single.FloatValue));
        Assert.Equal(MetadataValue.ValueOneofCase.DoubleValue, doublePrecision.ValueCase);
        Assert.True(double.IsPositiveInfinity(doublePrecision.DoubleValue));
    }

    [Fact]
    public void MetadataValueIntegratesGoogleDecimalWithoutNativeConversion()
    {
        GoogleDecimal decimalValue = new()
        {
            Value = "1234567890.123456789"
        };
        MetadataValue value = new()
        {
            DecimalValue = decimalValue
        };

        Assert.Equal(MetadataValue.ValueOneofCase.DecimalValue, value.ValueCase);
        Assert.Same(decimalValue, value.DecimalValue);
        Assert.Equal("1234567890.123456789", value.DecimalValue.Value);
    }

    [Fact]
    public void DateTimeValuePreservesAbsoluteInstantAndOptionalOffset()
    {
        DateTimeValue value = new()
        {
            Timestamp = Timestamp.FromDateTime(DateTime.SpecifyKind(
                new DateTime(2026, 9, 20, 18, 30, 0),
                DateTimeKind.Utc)),
            UtcOffset = Duration.FromTimeSpan(TimeSpan.FromHours(-5))
        };

        Assert.NotNull(value.Timestamp);
        Assert.NotNull(value.UtcOffset);
        Assert.Equal(-18_000, value.UtcOffset.Seconds);

        MetadataValue metadata = new()
        {
            DateTimeValue = value
        };

        Assert.Equal(MetadataValue.ValueOneofCase.DateTimeValue, metadata.ValueCase);
        Assert.Same(value, metadata.DateTimeValue);
    }

    [Fact]
    public void LogLevelMaintainsTheEstablishedNumericValues()
    {
        Assert.Equal(0, (int)LogLevel.Trace);
        Assert.Equal(1, (int)LogLevel.Debug);
        Assert.Equal(2, (int)LogLevel.Information);
        Assert.Equal(3, (int)LogLevel.Warning);
        Assert.Equal(4, (int)LogLevel.Error);
        Assert.Equal(5, (int)LogLevel.Critical);
    }

    [Fact]
    public void LogRequestDistinguishesAnOmittedFlowIdFromASuppliedFlowId()
    {
        LogRequest request = new()
        {
            Entry = new LogEntry
            {
                Message = "entry"
            }
        };

        Assert.False(request.HasFlowId);

        request.FlowId = "flow-1";

        Assert.True(request.HasFlowId);
        Assert.Equal("flow-1", request.FlowId);
    }

    [Fact]
    public void PopScopeRequestDistinguishesAnAbsentExpectedContext()
    {
        PopScopeRequest request = new()
        {
            FlowId = "flow-1"
        };

        Assert.Null(request.ExpectedContext);

        request.ExpectedContext = new LogContext
        {
            Source = "source"
        };

        Assert.NotNull(request.ExpectedContext);
        Assert.True(request.ExpectedContext.HasSource);
    }

    [Fact]
    public void GeneratedDescriptorsPreserveDocumentedFieldNumbers()
    {
        Assert.Equal(1, LogEntry.Descriptor.FindFieldByName("message").FieldNumber);
        Assert.Equal(2, LogEntry.Descriptor.FindFieldByName("level").FieldNumber);
        Assert.Equal(8, LogEntry.Descriptor.FindFieldByName("metadata").FieldNumber);
        Assert.Equal(7, MetadataValue.Descriptor.FindFieldByName("decimal_value").FieldNumber);
        Assert.Equal(9, MetadataValue.Descriptor.FindFieldByName("duration_value").FieldNumber);
        Assert.Equal(2, PopScopeRequest.Descriptor.FindFieldByName("expected_context").FieldNumber);
    }
}
