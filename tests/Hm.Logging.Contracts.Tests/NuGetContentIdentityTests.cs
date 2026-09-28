using System.IO.Compression;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Hm.Logging.Contracts.ReleaseTools;
using NuGet.Common;
using NuGet.Packaging;
using NuGet.Packaging.Signing;
using Xunit;

namespace Hm.Logging.Contracts.Tests;

public sealed class NuGetContentIdentityTests : IDisposable
{
    private readonly string _directory = Path.Combine(Path.GetTempPath(), $"hm-contracts-content-{Guid.NewGuid():N}");

    public NuGetContentIdentityTests()
    {
        _ = Directory.CreateDirectory(_directory);
    }

    [Fact]
    public void EquivalentPackagesAreAccepted()
    {
        string local = CreatePackage("local.nupkg", [1, 2, 3]);
        string remote = Path.Combine(_directory, "remote.nupkg");
        File.Copy(local, remote);
        Assert.Equal(0, Program.Main(["assert-content-identity", local, remote]));
    }

    [Fact]
    public void SameNominalIdentityWithDifferentContentIsRejected()
    {
        string local = CreatePackage("local.nupkg", [1, 2, 3]);
        string remote = CreatePackage("remote.nupkg", [3, 2, 1]);
        _ = Assert.Throws<InvalidDataException>(() => NuGetContentIdentity.AssertEquivalent(local, remote));
        Assert.Equal(1, Program.Main(["assert-content-identity", local, remote]));
    }

    [Fact]
    public void CorruptOrMissingPackageFailsClosed()
    {
        string local = CreatePackage("local.nupkg", [1, 2, 3]);
        string remote = Path.Combine(_directory, "remote.nupkg");
        Assert.Equal(1, Program.Main(["assert-content-identity", local, remote]));
        File.WriteAllBytes(remote, [1, 2, 3]);
        Assert.Equal(1, Program.Main(["assert-content-identity", local, remote]));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData(" ")]
    [InlineData("not-base64")]
    [InlineData("AQID")]
    public void MissingOrInvalidContentIdentityFailsClosed(string? value)
    {
        _ = Assert.Throws<InvalidDataException>(() => NuGetContentIdentity.ParseContentHash(value));
    }

    [Fact]
    public void OnlyCanonicalSha512IdentityIsAccepted()
    {
        string value = Convert.ToBase64String(new byte[64]);
        Assert.Equal(64, NuGetContentIdentity.ParseContentHash(value).Length);
        _ = Assert.Throws<InvalidDataException>(() => NuGetContentIdentity.ParseContentHash(value + "\n"));
    }

    [Fact]
    public void CommandRejectsInvalidArguments()
    {
        Assert.Equal(2, Program.Main([]));
        Assert.Equal(2, Program.Main(["unknown", "local", "remote"]));
    }

    [Fact]
    public async Task RepositorySigningPreservesContentIdentityDespiteDifferentArchiveBytes()
    {
        string local = CreatePackage("local.nupkg", [1, 2, 3]);
        string remote = Path.Combine(_directory, "remote.nupkg");
        await RepositorySignAsync(local, remote);
        Assert.False(File.ReadAllBytes(local).AsSpan().SequenceEqual(File.ReadAllBytes(remote)));
        using var package = new PackageArchiveReader(remote);
        PrimarySignature? signature = await package.GetPrimarySignatureAsync(TestContext.Current.CancellationToken);
        _ = Assert.IsType<RepositoryPrimarySignature>(signature);
        NuGetContentIdentity.AssertEquivalent(local, remote);
    }

    [Fact]
    public async Task SignedPackageWithModifiedPayloadFailsClosed()
    {
        string local = CreatePackage("local.nupkg", [1, 2, 3]);
        string remote = Path.Combine(_directory, "remote.nupkg");
        await RepositorySignAsync(local, remote);
        using (ZipArchive package = ZipFile.Open(remote, ZipArchiveMode.Update))
        {
            package.GetEntry("lib/net10.0/Hm.Logging.Contracts.dll")!.Delete();
            WriteEntry(package, "lib/net10.0/Hm.Logging.Contracts.dll", [3, 2, 1]);
        }

        Assert.Equal(1, Program.Main(["assert-content-identity", local, remote]));
    }

    [Fact]
    public async Task TamperedSignatureFailsClosed()
    {
        string local = CreatePackage("local.nupkg", [1, 2, 3]);
        string remote = Path.Combine(_directory, "remote.nupkg");
        await RepositorySignAsync(local, remote);
        byte[] signatureValue;
        using (var package = new PackageArchiveReader(remote))
        {
            PrimarySignature signature = (await package.GetPrimarySignatureAsync(TestContext.Current.CancellationToken))!;
            signatureValue = signature.GetSignatureValue();
        }

        byte[] archive = File.ReadAllBytes(remote);
        int offset = archive.AsSpan().IndexOf(signatureValue);
        Assert.True(offset >= 0, "NuGet stores its signature uncompressed.");
        archive[offset] ^= 1;
        File.WriteAllBytes(remote, archive);
        Assert.Equal(1, Program.Main(["assert-content-identity", local, remote]));
    }

    public void Dispose()
    {
        Directory.Delete(_directory, recursive: true);
    }

    private string CreatePackage(string name, byte[] payload)
    {
        string path = Path.Combine(_directory, name);
        using ZipArchive package = ZipFile.Open(path, ZipArchiveMode.Create);
        WriteEntry(package, "HDev.Hm.Logging.Contracts.nuspec", "<package><metadata><id>HDev.Hm.Logging.Contracts</id><version>1.0.0-preview.1</version><repository commit='1234567890123456789012345678901234567890'/></metadata></package>"u8.ToArray());
        WriteEntry(package, "lib/net10.0/Hm.Logging.Contracts.dll", payload);
        return path;
    }

    private static void WriteEntry(ZipArchive package, string name, byte[] bytes)
    {
        using Stream stream = package.CreateEntry(name).Open();
        stream.Write(bytes);
    }

    private static async Task RepositorySignAsync(string source, string destination)
    {
        // A real NuGet repository signature generated offline with a test-only certificate.
        // This exercises integrity, not a trust policy or the NuGet.org production key.
        using var key = RSA.Create(2048);
        var request = new CertificateRequest("CN=HM Contracts Content Identity Test", key, System.Security.Cryptography.HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, false));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, false));
        request.CertificateExtensions.Add(new X509EnhancedKeyUsageExtension([new Oid("1.3.6.1.5.5.7.3.3")], false));
        request.CertificateExtensions.Add(new X509SubjectKeyIdentifierExtension(request.PublicKey, false));
        using X509Certificate2 certificate = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(1));
        var input = new Lazy<Stream>(() => File.OpenRead(source));
        var output = new Lazy<Stream>(() => File.Open(destination, FileMode.Create, FileAccess.ReadWrite, FileShare.None));
        try
        {
            var options = new SigningOptions(input, output, overwrite: false, new X509SignatureProvider(new OfflineTimestampProvider()), NullLogger.Instance);
            var signRequest = new RepositorySignPackageRequest(certificate, NuGet.Common.HashAlgorithmName.SHA256,
                NuGet.Common.HashAlgorithmName.SHA256, new Uri("https://api.nuget.org/v3/index.json"), ["hm-contracts-test"]);
            await SigningUtility.SignAsync(options, signRequest, TestContext.Current.CancellationToken);
        }
        finally
        {
            if (input.IsValueCreated) { input.Value.Dispose(); }
            if (output.IsValueCreated) { output.Value.Dispose(); }
        }
    }

    private sealed class OfflineTimestampProvider : ITimestampProvider
    {
        public Task<PrimarySignature> TimestampSignatureAsync(PrimarySignature primarySignature,
            TimestampRequest request, ILogger logger, CancellationToken cancellationToken)
        {
            return Task.FromResult(primarySignature);
        }
    }
}
