using System.IO;

static partial class Program
{
    static string? FindRepoRoot(string start)
    {
        var dir = new DirectoryInfo(start);
        while (dir != null)
        {
            var docsMarker = File.Exists(Path.Combine(dir.FullName, "Docs", "MILESTONES.md"));
            var toolsMarker = Directory.Exists(Path.Combine(dir.FullName, "Tools", "M10GDriver"));
            var testsMarker = Directory.Exists(Path.Combine(dir.FullName, "Tests", "CommandTests"));

            if (docsMarker && toolsMarker && testsMarker)
                return dir.FullName;

            dir = dir.Parent;
        }
        return null;
    }

    static string Rel(string root, string path)
    {
        return Path.GetRelativePath(root, path);
    }
}
