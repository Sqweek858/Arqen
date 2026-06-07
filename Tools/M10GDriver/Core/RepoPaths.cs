using System.IO;

static partial class Program
{
    static string? FindRepoRoot(string start)
    {
        var dir = new DirectoryInfo(start);
        while (dir != null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, "Experiments")) &&
                File.Exists(Path.Combine(dir.FullName, "Docs", "MILESTONES.md")))
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
