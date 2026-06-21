using System.Text;

static partial class Program
{
    static string Esc(string value)
    {
        return value.Replace("\\", "\\\\").Replace("|", "\\p").Replace("\r", "\\r").Replace("\n", "\\n");
    }

    static string Unesc(string value)
    {
        var sb = new StringBuilder();
        for (var i = 0; i < value.Length; i++)
        {
            if (value[i] != '\\' || i + 1 >= value.Length)
            {
                sb.Append(value[i]);
                continue;
            }
            var next = value[++i];
            sb.Append(next switch
            {
                'p' => '|',
                'r' => '\r',
                'n' => '\n',
                '\\' => '\\',
                _ => next
            });
        }
        return sb.ToString();
    }
}
