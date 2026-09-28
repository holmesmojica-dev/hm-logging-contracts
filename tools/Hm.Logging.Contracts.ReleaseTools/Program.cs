namespace Hm.Logging.Contracts.ReleaseTools;

internal static class Program
{
    internal static int Main(string[] args)
    {
        if (args.Length != 3 || !string.Equals(args[0], "assert-content-identity", StringComparison.Ordinal))
        {
            Console.Error.WriteLine("Usage: assert-content-identity <local-package> <remote-package>");
            return 2;
        }

        try
        {
            NuGetContentIdentity.AssertEquivalent(args[1], args[2]);
            return 0;
        }
        catch (Exception exception)
        {
            Console.Error.WriteLine(exception.Message);
            return 1;
        }
    }
}
