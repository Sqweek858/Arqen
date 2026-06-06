using System.Text;

record Token(string Type, string Value, int Line, int Column);
record VarInfo(string Type, string Value);
record ExprResult(string Type, string Value, string Repr);
record AstModel(string Program, List<(string Name, string Type, string Value)> Vars, string Title, string Message, string MessageExpr, int ExitCode);

sealed class CompileError : Exception
{
    public string Stage { get; }
    public string Code { get; }
    public int Line { get; }
    public int Column { get; }

    public CompileError(string stage, string code, int line, int column, string message) : base(message)
    {
        Stage = stage;
        Code = code;
        Line = line;
        Column = column;
    }

    public string Format()
    {
        if (Line > 0 && Column > 0)
            return $"Error {Code} at line {Line}, column {Column}:\r\n{Message}\r\n";
        return $"Error {Code}:\r\n{Message}\r\n";
    }
}

static class Program
{
    static int Main(string[] args)
    {
        if (args.Length == 0 || args[0] is "-h" or "--help")
        {
            Console.WriteLine("Usage: arqc_m10g.exe <input.arq> [-o output.exe]");
            return args.Length == 0 ? 2 : 0;
        }

        string? inputArg = null;
        string? outputArg = null;

        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "-o")
            {
                if (i + 1 >= args.Length)
                {
                    Console.WriteLine("Error: -o requires an output path.");
                    return 2;
                }
                outputArg = args[++i];
            }
            else if (inputArg == null)
            {
                inputArg = args[i];
            }
            else
            {
                Console.WriteLine($"Error: unexpected argument: {args[i]}");
                return 2;
            }
        }

        if (inputArg == null)
        {
            Console.WriteLine("Error: missing input .arq path.");
            return 2;
        }

        var cwd = Directory.GetCurrentDirectory();
        var inputPath = Path.GetFullPath(Path.Combine(cwd, inputArg));
        if (!File.Exists(inputPath))
        {
            Console.WriteLine($"Error: input file not found: {inputPath}");
            return 2;
        }

        var repoRoot = FindRepoRoot(cwd) ?? FindRepoRoot(AppContext.BaseDirectory);
        if (repoRoot == null)
        {
            Console.WriteLine("Error: could not locate Arqen repo root.");
            return 2;
        }

        var stem = Path.GetFileNameWithoutExtension(inputPath);
        var buildRoot = Path.Combine(repoRoot, "Build");
        var tokenDir = Path.Combine(buildRoot, "Tokens");
        var astDir = Path.Combine(buildRoot, "AST");
        var exeDir = Path.Combine(buildRoot, "EXE");
        var errorDir = Path.Combine(buildRoot, "Errors");
        var logDir = Path.Combine(buildRoot, "Logs");

        foreach (var dir in new[] { tokenDir, astDir, exeDir, errorDir, logDir })
            Directory.CreateDirectory(dir);

        var tokenPath = Path.Combine(tokenDir, stem + ".tokens");
        var astPath = Path.Combine(astDir, stem + ".ast");
        var outputPath = outputArg == null
            ? Path.Combine(exeDir, stem + ".exe")
            : Path.GetFullPath(Path.Combine(cwd, outputArg));
        var outputDir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrWhiteSpace(outputDir))
            Directory.CreateDirectory(outputDir);

        var logPath = Path.Combine(logDir, stem + ".build.log");
        var log = new List<string>();

        void Emit(string line)
        {
            Console.WriteLine(line);
            log.Add(line);
        }

        string ErrorPath(string stage) => Path.Combine(errorDir, $"{stem}.{stage.ToLowerInvariant()}.error.txt");

        foreach (var old in Directory.GetFiles(errorDir, $"{stem}.*.error.txt"))
            File.Delete(old);

        try
        {
            var source = File.ReadAllText(inputPath, Encoding.UTF8);
            var tokens = Lex(source);
            File.WriteAllLines(tokenPath, tokens.Select(TokenLine), Encoding.UTF8);
            Emit($"[LEX] PASS -> {Rel(repoRoot, tokenPath)}");

            AstModel ast;
            try
            {
                ast = new Parser(tokens).Parse();
                Emit("[PARSE] PASS -> syntax OK");
                File.WriteAllLines(astPath, AstLines(ast), Encoding.UTF8);
                Emit($"[SEMANTIC] PASS -> {Rel(repoRoot, astPath)}");
            }
            catch (CompileError ex) when (ex.Stage is "PARSE" or "SEMANTIC")
            {
                var err = ErrorPath(ex.Stage);
                File.WriteAllText(err, ex.Format(), Encoding.UTF8);
                if (ex.Stage == "SEMANTIC")
                    Emit("[PARSE] PASS -> syntax OK");
                Emit($"[{ex.Stage}] FAIL {ex.Code} -> {Rel(repoRoot, err)}");
                Emit(ex.Stage == "PARSE" ? "Compiler stopped before semantic." : "Compiler stopped before codegen.");
                File.WriteAllLines(logPath, log, Encoding.UTF8);
                return 1;
            }

            try
            {
                Codegen(repoRoot, astPath, outputPath);
                Emit($"[CODEGEN] PASS -> {Rel(repoRoot, outputPath)}");
            }
            catch (CompileError ex)
            {
                var err = ErrorPath("CODEGEN");
                File.WriteAllText(err, ex.Format(), Encoding.UTF8);
                Emit($"[CODEGEN] FAIL {ex.Code} -> {Rel(repoRoot, err)}");
                File.WriteAllLines(logPath, log, Encoding.UTF8);
                return 1;
            }

            Emit("[BUILD] PASS");
            File.WriteAllLines(logPath, log, Encoding.UTF8);
            return 0;
        }
        catch (CompileError ex) when (ex.Stage == "LEX")
        {
            var err = ErrorPath("LEX");
            File.WriteAllText(err, ex.Format(), Encoding.UTF8);
            Emit($"[LEX] FAIL {ex.Code} -> {Rel(repoRoot, err)}");
            Emit("Compiler stopped before parser.");
            File.WriteAllLines(logPath, log, Encoding.UTF8);
            return 1;
        }
    }

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

    static List<Token> Lex(string source)
    {
        var tokens = new List<Token>();
        var i = 0;
        var line = 1;
        var col = 1;

        while (i < source.Length)
        {
            var ch = source[i];

            if (ch is ' ' or '\t')
            {
                i++;
                col++;
                continue;
            }

            if (ch == '\r' || ch == '\n')
            {
                var startCol = col;
                if (ch == '\r' && i + 1 < source.Length && source[i + 1] == '\n')
                    i += 2;
                else
                    i++;
                tokens.Add(new Token("NEWLINE", "", line, startCol));
                line++;
                col = 1;
                continue;
            }

            if (ch == '"')
            {
                var startLine = line;
                var startCol = col;
                i++;
                col++;
                var sb = new StringBuilder();
                while (i < source.Length && source[i] != '"')
                {
                    if (source[i] == '\r' || source[i] == '\n')
                        throw new CompileError("LEX", "L002", startLine, startCol, "Unterminated string.");
                    sb.Append(source[i]);
                    i++;
                    col++;
                }
                if (i >= source.Length)
                    throw new CompileError("LEX", "L002", startLine, startCol, "Unterminated string.");
                i++;
                col++;
                tokens.Add(new Token("STRING", sb.ToString(), startLine, startCol));
                continue;
            }

            if (char.IsLetter(ch) || ch == '_')
            {
                var startLine = line;
                var startCol = col;
                var sb = new StringBuilder();
                while (i < source.Length && (char.IsLetterOrDigit(source[i]) || source[i] == '_'))
                {
                    sb.Append(source[i]);
                    i++;
                    col++;
                }
                var word = sb.ToString();
                if (word is "true" or "false")
                    tokens.Add(new Token("BOOL", word, startLine, startCol));
                else if (word is "program" or "let" or "be" or "title" or "message" or "text" or "exit" or "end")
                    tokens.Add(new Token("KEYWORD", word, startLine, startCol));
                else
                    tokens.Add(new Token("IDENT", word, startLine, startCol));
                continue;
            }

            if (char.IsDigit(ch))
            {
                var startLine = line;
                var startCol = col;
                var sb = new StringBuilder();
                while (i < source.Length && char.IsDigit(source[i]))
                {
                    sb.Append(source[i]);
                    i++;
                    col++;
                }
                tokens.Add(new Token("INT", sb.ToString(), startLine, startCol));
                continue;
            }

            if (ch == '+')
            {
                tokens.Add(new Token("PLUS", "+", line, col));
                i++;
                col++;
                continue;
            }

            if (char.IsControl(ch))
                throw new CompileError("LEX", "L004", line, col, "Unexpected control character.");

            throw new CompileError("LEX", "L001", line, col, $"Unknown character '{ch}'.");
        }

        tokens.Add(new Token("EOF", "", line, col));
        return tokens;
    }

    static string TokenLine(Token t) => $"{t.Type}|{Esc(t.Value)}|{t.Line}|{t.Column}";

    static IEnumerable<string> AstLines(AstModel ast)
    {
        yield return $"PROGRAM|{Esc(ast.Program)}";
        foreach (var v in ast.Vars)
            yield return $"LET|{Esc(v.Name)}|{Esc(v.Type)}|{Esc(v.Value)}";
        yield return $"TITLE|{Esc(ast.Title)}";
        yield return $"MESSAGE|{Esc(ast.Message)}";
        yield return $"MESSAGE_EXPR|{Esc(ast.MessageExpr)}";
        yield return $"EXIT|{ast.ExitCode}";
        yield return "SEMANTIC|OK";
    }

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

    static void Codegen(string repoRoot, string astPath, string outputPath)
    {
        var fields = new Dictionary<string, string>();
        foreach (var line in File.ReadAllLines(astPath, Encoding.UTF8))
        {
            var parts = SplitStable(line);
            if (parts.Count >= 2 && parts[0] is "PROGRAM" or "TITLE" or "MESSAGE" or "EXIT" or "SEMANTIC")
                fields[parts[0]] = parts[1];
        }

        if (!fields.TryGetValue("TITLE", out var title) ||
            !fields.TryGetValue("MESSAGE", out var message) ||
            !fields.TryGetValue("EXIT", out var exitText) ||
            exitText != "0" ||
            !fields.TryGetValue("SEMANTIC", out var semantic) ||
            semantic != "OK")
            throw new CompileError("CODEGEN", "C001", 0, 0, "Invalid AST for M10G codegen.");

        var templatePath = Path.Combine(repoRoot, "Experiments", "M10_SimpleExpressions", "template_messagebox_m8.exe");
        if (!File.Exists(templatePath))
            throw new CompileError("CODEGEN", "C001", 0, 0, "Missing MessageBox PE template.");

        var pe = File.ReadAllBytes(templatePath);
        PatchUtf16(pe, 0x400, 64, message);
        PatchUtf16(pe, 0x440, 64, title);

        var tmpPath = outputPath + ".tmp";
        File.WriteAllBytes(tmpPath, pe);
        File.Move(tmpPath, outputPath, true);
    }

    static void PatchUtf16(byte[] pe, int offset, int maxBytes, string value)
    {
        var bytes = Encoding.Unicode.GetBytes(value + "\0");
        if (bytes.Length > maxBytes)
            throw new CompileError("CODEGEN", "C001", 0, 0, $"String too long for PE template buffer: {value}");
        Array.Clear(pe, offset, maxBytes);
        Array.Copy(bytes, 0, pe, offset, bytes.Length);
    }

    static List<string> SplitStable(string line)
    {
        var parts = new List<string>();
        var sb = new StringBuilder();
        var escaped = false;
        foreach (var ch in line)
        {
            if (escaped)
            {
                sb.Append('\\');
                sb.Append(ch);
                escaped = false;
                continue;
            }
            if (ch == '\\')
            {
                escaped = true;
                continue;
            }
            if (ch == '|')
            {
                parts.Add(Unesc(sb.ToString()));
                sb.Clear();
                continue;
            }
            sb.Append(ch);
        }
        if (escaped)
            sb.Append('\\');
        parts.Add(Unesc(sb.ToString()));
        return parts;
    }

    sealed class Parser
    {
        readonly List<Token> _tokens;
        readonly Dictionary<string, VarInfo> _vars = new(StringComparer.Ordinal);
        readonly List<(string Name, string Type, string Value)> _varList = new();
        int _pos;

        public Parser(List<Token> tokens)
        {
            _tokens = tokens;
        }

        public AstModel Parse()
        {
            SkipNewlines();
            ExpectKeyword("program");
            var program = ExpectName("program name");
            ExpectLine();

            SkipNewlines();
            while (IsKeyword("let"))
            {
                ParseLet();
                SkipNewlines();
            }

            ExpectKeyword("title");
            var titleTok = Expect("STRING", "title string");
            ExpectLine();

            SkipNewlines();
            ExpectKeyword("message");
            ExpectKeyword("text");
            var expr = ParseExpression();
            ExpectLine();

            SkipNewlines();
            ExpectKeyword("exit");
            var exitTok = Expect("INT", "exit code");
            if (exitTok.Value != "0")
                throw new CompileError("SEMANTIC", "S013", exitTok.Line, exitTok.Column, "Only exit 0 is supported in M10G.");
            ExpectLine();

            SkipNewlines();
            ExpectKeyword("end");
            ExpectKeyword("program");
            var endName = ExpectName("end program name");
            if (endName != program)
                throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "end program name does not match program name.");
            ExpectLineOrEof();
            SkipNewlines();
            Expect("EOF", "end of file");

            return new AstModel(program, _varList, titleTok.Value, expr.Value, expr.Repr, 0);
        }

        void ParseLet()
        {
            ExpectKeyword("let");
            if (!CurrentIs("IDENT"))
                throw new CompileError("SEMANTIC", "S002", Current.Line, Current.Column, "Invalid variable name.");
            var nameTok = Advance();
            if (_vars.ContainsKey(nameTok.Value))
                throw new CompileError("SEMANTIC", "S001", nameTok.Line, nameTok.Column, $"Variable \"{nameTok.Value}\" is already defined.");
            ExpectKeyword("be");

            if (CurrentIs("NEWLINE") || CurrentIs("EOF"))
                throw new CompileError("PARSE", "P012", Current.Line, Current.Column, "Expected value after \"be\".");

            string type;
            string value;
            if (CurrentIs("STRING"))
            {
                var t = Advance();
                type = "text";
                value = t.Value;
            }
            else if (CurrentIs("INT"))
            {
                var t = Advance();
                type = "int";
                value = t.Value;
            }
            else if (CurrentIs("BOOL"))
            {
                var t = Advance();
                type = "bool";
                value = t.Value;
            }
            else if (CurrentIs("IDENT"))
            {
                throw new CompileError("SEMANTIC", "S003", Current.Line, Current.Column, "Unknown variable reference in let value.");
            }
            else
            {
                throw new CompileError("SEMANTIC", "T001", Current.Line, Current.Column, "Unknown literal type for variable.");
            }

            _vars[nameTok.Value] = new VarInfo(type, value);
            _varList.Add((nameTok.Value, type, value));
            ExpectLine();
        }

        ExprResult ParseExpression()
        {
            if (CurrentIs("NEWLINE") || CurrentIs("EOF"))
                throw new CompileError("PARSE", "P010", Current.Line, Current.Column, "Expected expression after message text.");

            var left = ParsePrimary(afterPlus: false);
            var sawPlus = false;

            while (CurrentIs("PLUS"))
            {
                sawPlus = true;
                Advance();
                if (CurrentIs("NEWLINE") || CurrentIs("EOF"))
                    throw new CompileError("PARSE", "P011", Current.Line, Current.Column, "Expected expression after +.");
                var right = ParsePrimary(afterPlus: true);
                if (left.Type != "text" || right.Type != "text")
                    throw new CompileError("SEMANTIC", "S011", Current.Line, Current.Column, "Type mismatch in expression. Only text concatenation is supported in M10G.");
                left = new ExprResult("text", left.Value + right.Value, $"plus({left.Repr},{right.Repr})");
            }

            if (!sawPlus && left.Type != "text")
                throw new CompileError("SEMANTIC", "S012", Current.Line, Current.Column, "message text requires text expression.");

            if (left.Type != "text")
                throw new CompileError("SEMANTIC", "S013", Current.Line, Current.Column, "Unsupported expression type in M10G.");

            return left;
        }

        ExprResult ParsePrimary(bool afterPlus)
        {
            if (CurrentIs("STRING"))
            {
                var t = Advance();
                return new ExprResult("text", t.Value, $"str(\"{t.Value}\")");
            }

            if (CurrentIs("IDENT"))
            {
                var t = Advance();
                if (!_vars.TryGetValue(t.Value, out var info))
                    throw new CompileError("SEMANTIC", "S010", t.Line, t.Column, $"Unknown variable \"{t.Value}\".");
                return new ExprResult(info.Type, info.Value, $"var({t.Value})");
            }

            if (CurrentIs("INT"))
            {
                var t = Advance();
                return new ExprResult("int", t.Value, $"int({t.Value})");
            }

            if (CurrentIs("BOOL"))
            {
                var t = Advance();
                return new ExprResult("bool", t.Value, $"bool({t.Value})");
            }

            if (afterPlus)
                throw new CompileError("PARSE", "P011", Current.Line, Current.Column, "Expected expression after +.");

            throw new CompileError("PARSE", "P010", Current.Line, Current.Column, "Expected expression after message text.");
        }

        string ExpectName(string what)
        {
            if (CurrentIs("STRING") || CurrentIs("IDENT"))
                return Advance().Value;
            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, $"Expected {what}.");
        }

        void ExpectKeyword(string value)
        {
            if (Current.Type == "KEYWORD" && Current.Value == value)
            {
                Advance();
                return;
            }
            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, $"Expected keyword \"{value}\".");
        }

        Token Expect(string type, string what)
        {
            if (CurrentIs(type))
                return Advance();
            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, $"Expected {what}.");
        }

        void ExpectLine()
        {
            if (CurrentIs("NEWLINE"))
            {
                Advance();
                return;
            }
            if (CurrentIs("EOF"))
                return;
            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected end of line.");
        }

        void ExpectLineOrEof()
        {
            if (CurrentIs("NEWLINE"))
            {
                Advance();
                return;
            }
            if (CurrentIs("EOF"))
                return;
            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected end of line.");
        }

        void SkipNewlines()
        {
            while (CurrentIs("NEWLINE"))
                Advance();
        }

        bool IsKeyword(string value) => Current.Type == "KEYWORD" && Current.Value == value;
        bool CurrentIs(string type) => Current.Type == type;
        Token Current => _tokens[Math.Min(_pos, _tokens.Count - 1)];
        Token Advance() => _tokens[_pos++];
    }
}
