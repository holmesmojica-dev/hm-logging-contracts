using System.Security.Cryptography;
using NuGet.Packaging;
using NuGet.Packaging.Signing;

namespace Hm.Logging.Contracts.ReleaseTools;

internal static class NuGetContentIdentity
{
    internal static void AssertEquivalent(string localPackagePath, string remotePackagePath)
    {
        byte[] localHash = ReadContentHash(localPackagePath);
        byte[] remoteHash = ReadContentHash(remotePackagePath);
        if (!CryptographicOperations.FixedTimeEquals(localHash, remoteHash))
        {
            throw new InvalidDataException("The remote NuGet package content identity differs from the validated local artifact.");
        }
    }

    private static byte[] ReadContentHash(string packagePath)
    {
        using var package = new PackageArchiveReader(packagePath);
        CancellationToken token = CancellationToken.None;
        if (package.IsSignedAsync(token).GetAwaiter().GetResult())
        {
            PrimarySignature signature = package.GetPrimarySignatureAsync(token).GetAwaiter().GetResult()
                ?? throw new InvalidDataException("The signed NuGet package has no primary signature.");
            // Verify cryptographic integrity, not certificate trust/revocation policy.
            // Both the CMS signature and the package payload must be intact before
            // trusting the unsigned-package identity carried by repository signing.
            signature.SignedCms.CheckSignature(verifySignatureOnly: true);
            package.ValidateIntegrityAsync(signature.SignatureContent, token).GetAwaiter().GetResult();
        }

        return ParseContentHash(package.GetContentHash(token));
    }

    internal static byte[] ParseContentHash(string? contentHash)
    {
        if (string.IsNullOrWhiteSpace(contentHash))
        {
            throw new InvalidDataException("The NuGet package content identity is missing.");
        }

        byte[] bytes;
        try
        {
            bytes = Convert.FromBase64String(contentHash);
        }
        catch (FormatException exception)
        {
            throw new InvalidDataException("The NuGet package content identity is invalid Base64.", exception);
        }

        return bytes.Length == 64 && string.Equals(Convert.ToBase64String(bytes), contentHash, StringComparison.Ordinal)
            ? bytes
            : throw new InvalidDataException("The NuGet package content identity is not a canonical SHA-512 value.");
    }
}
