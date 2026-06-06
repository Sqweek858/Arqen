using System.Text;

record Token(string Type, string Value, int Line, int Column);
record VarInfo(string Type, string Value);
record ExprResult(string Type, string Value, string Repr);
record CompareResult(bool Value, string Repr);
record AstModel(string Program, List<(string Name, string Type, string Value)> Vars, string Title, string TitleExpr, string TitleCommand, string Message, string MessageExpr, string MessageCommand, int ExitCode, string FinalCommand, List<string> Flow);

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
            Console.WriteLine("       arqc_m10g.exe --backend-only <input.arqir> [-o output.exe]");
            return args.Length == 0 ? 2 : 0;
        }

        string? inputArg = null;
        string? outputArg = null;
        var backendOnly = false;

        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "--backend-only")
            {
                backendOnly = true;
            }
            else if (args[i] == "-o")
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
        var irDir = Path.Combine(buildRoot, "IR");
        var exeDir = Path.Combine(buildRoot, "EXE");
        var errorDir = Path.Combine(buildRoot, "Errors");
        var manifestDir = Path.Combine(buildRoot, "Manifests");
        var logDir = Path.Combine(buildRoot, "Logs");
        var diagnosticsRoot = Path.Combine(buildRoot, "Diagnostics");
        var diagnosticsLexer = Path.Combine(diagnosticsRoot, "Lexer");
        var diagnosticsParser = Path.Combine(diagnosticsRoot, "Parser");
        var diagnosticsSemantic = Path.Combine(diagnosticsRoot, "Semantic");
        var diagnosticsIr = Path.Combine(diagnosticsRoot, "IR");
        var diagnosticsBackend = Path.Combine(diagnosticsRoot, "Backend");

        foreach (var dir in new[] { tokenDir, astDir, irDir, exeDir, errorDir, manifestDir, logDir, diagnosticsLexer, diagnosticsParser, diagnosticsSemantic, diagnosticsIr, diagnosticsBackend })
            Directory.CreateDirectory(dir);

        var tokenPath = Path.Combine(tokenDir, stem + ".tokens");
        var astPath = Path.Combine(astDir, stem + ".ast");
        var irPath = Path.Combine(irDir, stem + ".arqir");
        var outputPath = outputArg == null
            ? Path.Combine(exeDir, stem + ".exe")
            : Path.GetFullPath(Path.Combine(cwd, outputArg));
        var outputDir = Path.GetDirectoryName(outputPath);
        if (!string.IsNullOrWhiteSpace(outputDir))
            Directory.CreateDirectory(outputDir);

        var logPath = Path.Combine(logDir, stem + ".build.log");
        var manifestPath = Path.Combine(manifestDir, stem + ".manifest.txt");
        var log = new List<string>();

        void Emit(string line)
        {
            Console.WriteLine(line);
            log.Add(line);
        }

        string ErrorPath(string stage) => Path.Combine(errorDir, $"{stem}.{stage.ToLowerInvariant()}.error.txt");
        string DiagnosticPath(string stage) => Path.Combine(stage.ToUpperInvariant() switch
        {
            "LEX" => diagnosticsLexer,
            "PARSE" => diagnosticsParser,
            "SEMANTIC" => diagnosticsSemantic,
            "IR" => diagnosticsIr,
            "BACKEND" or "CODEGEN" => diagnosticsBackend,
            _ => errorDir
        }, $"{stem}.{stage.ToLowerInvariant()}.diagnostic.txt");

        void WriteStageError(string stage, CompileError ex)
        {
            var text = ex.Format();
            File.WriteAllText(ErrorPath(stage), text, Encoding.UTF8);
            File.WriteAllText(DiagnosticPath(stage), text, Encoding.UTF8);
        }

        foreach (var old in Directory.GetFiles(errorDir, $"{stem}.*.error.txt"))
            File.Delete(old);
        foreach (var dir in new[] { diagnosticsLexer, diagnosticsParser, diagnosticsSemantic, diagnosticsIr, diagnosticsBackend })
            foreach (var old in Directory.GetFiles(dir, $"{stem}.*.diagnostic.txt"))
                File.Delete(old);

        if (backendOnly)
        {
            try
            {
                var backendManifestPath = Path.Combine(manifestDir, Path.GetFileNameWithoutExtension(outputPath) + ".manifest.txt");
                BackendFromIr(repoRoot, inputPath, outputPath);
                WriteManifest(backendManifestPath, Rel(repoRoot, outputPath), SourceFromIr(inputPath), Rel(repoRoot, inputPath), "WindowsX64PE_MessageBoxBackend", "windows-x64-pe", "success");
                Emit($"[BACKEND] PASS -> {Rel(repoRoot, outputPath)}");
                Emit($"[ARTIFACT] PASS -> {Rel(repoRoot, backendManifestPath)}");
                File.WriteAllLines(logPath, log, Encoding.UTF8);
                return 0;
            }
            catch (CompileError ex)
            {
                WriteStageError("BACKEND", ex);
                Emit($"[BACKEND] FAIL {ex.Code} -> {Rel(repoRoot, ErrorPath("BACKEND"))}");
                File.WriteAllLines(logPath, log, Encoding.UTF8);
                return 1;
            }
        }

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
                WriteStageError(ex.Stage, ex);
                if (ex.Stage == "SEMANTIC")
                    Emit("[PARSE] PASS -> syntax OK");
                Emit($"[{ex.Stage}] FAIL {ex.Code} -> {Rel(repoRoot, ErrorPath(ex.Stage))}");
                Emit(ex.Stage == "PARSE" ? "Compiler stopped before semantic." : "Compiler stopped before codegen.");
                File.WriteAllLines(logPath, log, Encoding.UTF8);
                return 1;
            }

            try
            {
                File.WriteAllLines(irPath, IrLines(ast, Rel(repoRoot, inputPath)), Encoding.UTF8);
                Emit($"[IR] PASS -> {Rel(repoRoot, irPath)}");
                BackendFromIr(repoRoot, irPath, outputPath);
                Emit($"[BACKEND] PASS -> {Rel(repoRoot, outputPath)}");
                WriteManifest(manifestPath, Rel(repoRoot, outputPath), Rel(repoRoot, inputPath), Rel(repoRoot, irPath), "WindowsX64PE_MessageBoxBackend", "windows-x64-pe", "success");
                Emit($"[ARTIFACT] PASS -> {Rel(repoRoot, manifestPath)}");
            }
            catch (CompileError ex)
            {
                var stage = ex.Stage == "IR" ? "IR" : "BACKEND";
                WriteStageError(stage, ex);
                Emit($"[{stage}] FAIL {ex.Code} -> {Rel(repoRoot, ErrorPath(stage))}");
                File.WriteAllLines(logPath, log, Encoding.UTF8);
                return 1;
            }

            Emit("[BUILD] PASS");
            File.WriteAllLines(logPath, log, Encoding.UTF8);
            return 0;
        }
        catch (CompileError ex) when (ex.Stage == "LEX")
        {
            WriteStageError("LEX", ex);
            Emit($"[LEX] FAIL {ex.Code} -> {Rel(repoRoot, ErrorPath("LEX"))}");
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

            if (ch == '/' && i + 1 < source.Length && source[i + 1] == '/')
            {
                while (i < source.Length && source[i] != '\r' && source[i] != '\n')
                {
                    i++;
                    col++;
                }
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
                else if (word is "program" or "let" or "be" or "title" or "message" or "text" or "show" or "set" or "to" or "exit" or "blend" or "mix" or "code" or "end" or "if" or "else" or "is" or "not")
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
        foreach (var line in ast.Flow)
            yield return line;
        if (ast.TitleCommand == "set_title_to")
            yield return $"SET_TITLE|{Esc(ast.Title)}";
        yield return $"TITLE|{Esc(ast.Title)}";
        yield return $"TITLE_EXPR|{Esc(ast.TitleExpr)}";
        if (ast.MessageCommand == "show_message")
            yield return $"SHOW_MESSAGE|{Esc(ast.Message)}";
        yield return $"MESSAGE|{Esc(ast.Message)}";
        yield return $"MESSAGE_EXPR|{Esc(ast.MessageExpr)}";
        if (ast.FinalCommand == "blend_mix_to_code")
            yield return $"BLEND_MIX_TO_CODE|{ast.ExitCode}";
        else
            yield return $"EXIT|{ast.ExitCode}";
        yield return "SEMANTIC|OK";
    }

    static IEnumerable<string> IrLines(AstModel ast, string sourcePath)
    {
        yield return "ARQIR|version=0";
        yield return $"TARGET|kind=program|name={Esc(ast.Program)}";
        yield return $"META|source={Esc(sourcePath.Replace('\\', '/'))}";
        yield return $"CONST|id=str_0|type=text|value={Esc(ast.Title)}";
        yield return $"CONST|id=str_1|type=text|value={Esc(ast.Message)}";
        yield return $"CONST|id=i32_0|type=int|value={ast.ExitCode}";
        yield return "ACTION|id=act_0|op=show_message|title=str_0|text=str_1";
        yield return "ACTION|id=act_1|op=exit|code=i32_0";
        yield return "ENTRY|actions=act_0,act_1";
        yield return "END";
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

    static void BackendFromIr(string repoRoot, string irPath, string outputPath)
    {
        var ir = ParseIr(irPath);

        if (ir.Version != "0")
            throw new CompileError("BACKEND", "B001", 0, 0, "Unsupported ARQIR version.");

        if (!ir.Actions.TryGetValue("act_0", out var show) ||
            !show.TryGetValue("op", out var showOp) ||
            showOp != "show_message")
            throw new CompileError("BACKEND", "B001", 0, 0, "Missing supported show_message action.");

        if (!show.TryGetValue("title", out var titleId) ||
            !show.TryGetValue("text", out var textId) ||
            !ir.Consts.TryGetValue(titleId, out var titleConst) ||
            !ir.Consts.TryGetValue(textId, out var textConst) ||
            titleConst.Type != "text" ||
            textConst.Type != "text")
            throw new CompileError("BACKEND", "B001", 0, 0, "Invalid show_message constants.");

        if (!ir.Actions.TryGetValue("act_1", out var exit) ||
            !exit.TryGetValue("op", out var exitOp) ||
            exitOp != "exit" ||
            !exit.TryGetValue("code", out var codeId) ||
            !ir.Consts.TryGetValue(codeId, out var codeConst) ||
            codeConst.Type != "int" ||
            codeConst.Value != "0")
            throw new CompileError("BACKEND", "B001", 0, 0, "Only exit code 0 is supported by this backend.");

        var templatePath = Path.Combine(repoRoot, "Experiments", "M10_SimpleExpressions", "template_messagebox_m8.exe");
        if (!File.Exists(templatePath))
            throw new CompileError("BACKEND", "B001", 0, 0, "Missing MessageBox PE template.");

        var pe = File.ReadAllBytes(templatePath);
        PatchUtf16(pe, 0x400, 64, textConst.Value);
        PatchUtf16(pe, 0x440, 64, titleConst.Value);

        var tmpPath = outputPath + ".tmp";
        File.WriteAllBytes(tmpPath, pe);
        File.Move(tmpPath, outputPath, true);
    }

    record IrConst(string Type, string Value);
    record IrModel(string Version, string Source, Dictionary<string, IrConst> Consts, Dictionary<string, Dictionary<string, string>> Actions);

    static IrModel ParseIr(string irPath)
    {
        if (!File.Exists(irPath))
            throw new CompileError("BACKEND", "B001", 0, 0, "IR file not found.");

        string? version = null;
        var source = "";
        var consts = new Dictionary<string, IrConst>(StringComparer.Ordinal);
        var actions = new Dictionary<string, Dictionary<string, string>>(StringComparer.Ordinal);
        var sawEnd = false;

        foreach (var raw in File.ReadAllLines(irPath, Encoding.UTF8))
        {
            if (string.IsNullOrWhiteSpace(raw))
                continue;

            var parts = SplitStable(raw);
            var op = parts[0];
            var fields = KeyValues(parts.Skip(1));

            switch (op)
            {
                case "ARQIR":
                    fields.TryGetValue("version", out version);
                    break;
                case "META":
                    fields.TryGetValue("source", out source);
                    break;
                case "CONST":
                    if (!fields.TryGetValue("id", out var id) ||
                        !fields.TryGetValue("type", out var type) ||
                        !fields.TryGetValue("value", out var value))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed CONST in IR.");
                    consts[id] = new IrConst(type, value);
                    break;
                case "ACTION":
                    if (!fields.TryGetValue("id", out var actionId))
                        throw new CompileError("BACKEND", "B001", 0, 0, "Malformed ACTION in IR.");
                    actions[actionId] = fields;
                    break;
                case "END":
                    sawEnd = true;
                    break;
            }
        }

        if (version == null || !sawEnd)
            throw new CompileError("BACKEND", "B001", 0, 0, "Invalid ARQIR file.");

        return new IrModel(version, source ?? "", consts, actions);
    }

    static Dictionary<string, string> KeyValues(IEnumerable<string> parts)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var part in parts)
        {
            var at = part.IndexOf('=');
            if (at <= 0)
                continue;
            result[part[..at]] = part[(at + 1)..];
        }
        return result;
    }

    static string SourceFromIr(string irPath)
    {
        try
        {
            return ParseIr(irPath).Source;
        }
        catch
        {
            return "";
        }
    }

    static void WriteManifest(string manifestPath, string artifactPath, string sourcePath, string irPath, string backend, string target, string status)
    {
        var lines = new[]
        {
            $"ARTIFACT|{Esc(artifactPath.Replace('\\', '/'))}",
            $"SOURCE|{Esc(sourcePath.Replace('\\', '/'))}",
            $"IR|{Esc(irPath.Replace('\\', '/'))}",
            $"BACKEND|{backend}",
            $"TARGET|{target}",
            $"STATUS|{status}",
            "ACTIONS|show_message,exit",
            "EXIT_CODE|0",
            $"CREATED_AT|{DateTimeOffset.Now:O}"
        };
        File.WriteAllLines(manifestPath, lines, Encoding.UTF8);
    }

    static void PatchUtf16(byte[] pe, int offset, int maxBytes, string value)
    {
        var bytes = Encoding.Unicode.GetBytes(value + "\0");
        if (bytes.Length > maxBytes)
            throw new CompileError("BACKEND", "B001", 0, 0, $"String too long for PE template buffer: {value}");
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
        readonly List<string> _flow = new();
        int _pos;
        string? _title;
        string _titleExpr = "";
        string _titleCommand = "";
        string? _message;
        string _messageExpr = "";
        string _messageCommand = "";
        string _finalCommand = "";
        int _exitCode = 0;
        int _ifDepth = 0;

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
            while (!CurrentIs("EOF") && !IsEndProgram())
            {
                ParseStatement(apply: true, inIf: false);
                SkipNewlines();
            }

            if (_title == null)
                throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected title command.");
            if (_message == null)
                throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected message command.");
            if (_finalCommand == "")
                throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected final command.");

            SkipNewlines();
            ExpectKeyword("end");
            ExpectKeyword("program");
            var endName = ExpectName("end program name");
            if (endName != program)
                throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "end program name does not match program name.");
            ExpectLineOrEof();
            SkipNewlines();
            Expect("EOF", "end of file");

            return new AstModel(program, _varList, _title!, _titleExpr, _titleCommand, _message!, _messageExpr, _messageCommand, _exitCode, _finalCommand, _flow);
        }

        void ParseStatement(bool apply, bool inIf)
        {
            SkipNewlines();

            if (CurrentIs("EOF"))
                throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected statement.");

            if (IsKeyword("let"))
            {
                if (inIf)
                    throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "let declarations inside compile-time if are not supported in M13.");
                ParseLet();
                return;
            }

            if (IsKeyword("title") || IsKeyword("set"))
            {
                var title = IsKeyword("title") ? ParseTitleCommand() : ParseSetTitleTo();
                if (apply)
                {
                    _title = title.Value;
                    _titleExpr = title.Repr;
                    _titleCommand = title.Command;
                }
                return;
            }

            if (IsKeyword("message") || IsKeyword("show"))
            {
                var message = IsKeyword("message") ? ParseMessageCommand() : ParseShowMessage();
                if (apply)
                {
                    _message = message.Value;
                    _messageExpr = message.Repr;
                    _messageCommand = message.Command;
                }
                return;
            }

            if (IsKeyword("exit"))
            {
                ParseExit();
                if (apply)
                    _finalCommand = "exit";
                return;
            }

            if (IsKeyword("blend"))
            {
                ParseBlendMixToCode();
                if (apply)
                    _finalCommand = "blend_mix_to_code";
                return;
            }

            if (IsKeyword("if"))
            {
                if (inIf || _ifDepth > 0)
                    throw new CompileError("PARSE", "P054", Current.Line, Current.Column, "Nested if statements are not supported in M13.");
                ParseCompileTimeIf(apply);
                return;
            }

            if (IsKeyword("else"))
                throw new CompileError("PARSE", "P055", Current.Line, Current.Column, "Unexpected else without matching if.");

            if (IsKeyword("end") && PeekKeyword("if"))
                throw new CompileError("PARSE", "P056", Current.Line, Current.Column, "Unexpected end if without matching if.");

            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected statement.");
        }

        void ParseCompileTimeIf(bool apply)
        {
            ExpectKeyword("if");
            if (CurrentIs("NEWLINE") || CurrentIs("EOF"))
                throw new CompileError("PARSE", "P053", Current.Line, Current.Column, "Expected condition after \"if\".");

            var condition = ParseComparison();
            ExpectLine();
            _flow.Add($"IF_COMPILE_TIME|condition={Esc(condition.Repr)}|value={condition.Value.ToString().ToLowerInvariant()}");

            _ifDepth++;
            SkipNewlines();
            while (!CurrentIs("EOF") && !IsKeyword("else") && !IsKeyword("end"))
            {
                ParseStatement(apply && condition.Value, inIf: true);
                SkipNewlines();
            }

            var sawElse = false;
            if (IsKeyword("else"))
            {
                sawElse = true;
                ExpectKeyword("else");
                ExpectLine();
                SkipNewlines();
                while (!CurrentIs("EOF") && !IsKeyword("end"))
                {
                    ParseStatement(apply && !condition.Value, inIf: true);
                    SkipNewlines();
                }
            }

            if (!IsEndIf())
                throw new CompileError("PARSE", "P057", Current.Line, Current.Column, "Expected end if.");

            ExpectKeyword("end");
            ExpectKeyword("if");
            ExpectLine();
            _ifDepth--;

            var selected = condition.Value ? "then" : (sawElse ? "else" : "none");
            _flow.Add($"IF_BRANCH_SELECTED|{selected}");
        }

        CommandExpr ParseTitleCommand()
        {
            if (IsKeyword("title"))
            {
                ExpectKeyword("title");
                var titleTok = Expect("STRING", "title string");
                ExpectLine();
                return new CommandExpr(titleTok.Value, $"str(\"{titleTok.Value}\")", "title");
            }

            if (IsKeyword("set"))
                return ParseSetTitleTo();

            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected title command.");
        }

        CommandExpr ParseSetTitleTo()
        {
            ExpectKeyword("set");
            if (!IsKeyword("title"))
                throw new CompileError("PARSE", "P050", Current.Line, Current.Column, "Expected keyword \"title\" after \"set\".");
            ExpectKeyword("title");
            if (!IsKeyword("to"))
                throw new CompileError("PARSE", "P051", Current.Line, Current.Column, "Expected keyword \"to\" after \"set title\".");
            ExpectKeyword("to");
            var expr = ParseExpression("set title to", "P052", "Expected expression after set title to.");
            ExpectLine();
            return new CommandExpr(expr.Value, expr.Repr, "set_title_to");
        }

        CommandExpr ParseMessageCommand()
        {
            if (IsKeyword("message"))
            {
                ExpectKeyword("message");
                ExpectKeyword("text");
                var expr = ParseExpression("message text", "P010", "Expected expression after message text.");
                ExpectLine();
                return new CommandExpr(expr.Value, expr.Repr, "message_text");
            }

            if (IsKeyword("show"))
                return ParseShowMessage();

            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected message command.");
        }

        CommandExpr ParseShowMessage()
        {
            ExpectKeyword("show");
            if (!IsKeyword("message"))
                throw new CompileError("PARSE", "P060", Current.Line, Current.Column, "Expected keyword \"message\" after \"show\".");
            ExpectKeyword("message");
            var expr = ParseExpression("show message", "P061", "Expected expression after show message.");
            ExpectLine();
            return new CommandExpr(expr.Value, expr.Repr, "show_message");
        }

        string ParseExit()
        {
            ExpectKeyword("exit");
            var exitTok = Expect("INT", "exit code");
            if (exitTok.Value != "0")
                throw new CompileError("SEMANTIC", "S013", exitTok.Line, exitTok.Column, "Only exit 0 is supported in M10G.");
            ExpectLine();
            return "exit";
        }

        string ParseBlendMixToCode()
        {
            ExpectKeyword("blend");
            if (!IsKeyword("mix"))
                throw new CompileError("PARSE", "P040", Current.Line, Current.Column, "Expected keyword \"mix\" after \"blend\".");
            ExpectKeyword("mix");
            if (!IsKeyword("to"))
                throw new CompileError("PARSE", "P041", Current.Line, Current.Column, "Expected keyword \"to\" after \"blend mix\".");
            ExpectKeyword("to");
            if (!IsKeyword("code"))
                throw new CompileError("PARSE", "P042", Current.Line, Current.Column, "Expected keyword \"code\" after \"blend mix to\".");
            ExpectKeyword("code");
            if (!CurrentIs("INT"))
                throw new CompileError("PARSE", "P043", Current.Line, Current.Column, "Expected integer after \"blend mix to code\".");
            var codeTok = Advance();
            if (codeTok.Value != "0")
                throw new CompileError("SEMANTIC", "S021", codeTok.Line, codeTok.Column, "blend mix to code only supports 0 currently.");
            ExpectLine();
            return "blend_mix_to_code";
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

        CompareResult ParseComparison()
        {
            var left = ParseComparisonOperand("P052", "Expected comparison left operand.");
            if (!IsKeyword("is"))
                throw new CompileError("PARSE", "P052", Current.Line, Current.Column, "Invalid comparison expression. Expected \"is\".");
            ExpectKeyword("is");

            var isNot = false;
            if (IsKeyword("not"))
            {
                isNot = true;
                ExpectKeyword("not");
            }

            if (CurrentIs("NEWLINE") || CurrentIs("EOF"))
            {
                var code = isNot ? "P051" : "P050";
                var text = isNot ? "Expected right operand after \"is not\"." : "Expected right operand after \"is\".";
                throw new CompileError("PARSE", code, Current.Line, Current.Column, text);
            }

            var right = ParseComparisonOperand(isNot ? "P051" : "P050", isNot ? "Expected right operand after \"is not\"." : "Expected right operand after \"is\".");
            if (left.Type != right.Type)
                throw new CompileError("SEMANTIC", "S021", Current.Line, Current.Column, $"Comparison type mismatch: {left.Type} and {right.Type}.");

            var equal = string.Equals(left.Value, right.Value, StringComparison.Ordinal);
            var value = isNot ? !equal : equal;
            var op = isNot ? "COMPARE_IS_NOT" : "COMPARE_IS";
            return new CompareResult(value, $"{op}|left={left.Repr}|right={right.Repr}");
        }

        ExprResult ParseComparisonOperand(string code, string message)
        {
            if (CurrentIs("STRING"))
            {
                var t = Advance();
                return new ExprResult("text", t.Value, $"str(\"{t.Value}\")");
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

            if (CurrentIs("IDENT"))
            {
                var t = Advance();
                if (!_vars.TryGetValue(t.Value, out var info))
                    throw new CompileError("SEMANTIC", "S020", t.Line, t.Column, $"Unknown variable \"{t.Value}\" in comparison.");
                return new ExprResult(info.Type, info.Value, $"var({t.Value})");
            }

            throw new CompileError("PARSE", code, Current.Line, Current.Column, message);
        }

        record CommandExpr(string Value, string Repr, string Command);

        ExprResult ParseExpression(string context, string missingCode, string missingMessage)
        {
            if (CurrentIs("NEWLINE") || CurrentIs("EOF"))
                throw new CompileError("PARSE", missingCode, Current.Line, Current.Column, missingMessage);

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
                throw new CompileError("SEMANTIC", "S012", Current.Line, Current.Column, $"{context} requires text expression.");

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

        bool IsEndProgram() => IsKeyword("end") && PeekKeyword("program");
        bool IsEndIf() => IsKeyword("end") && PeekKeyword("if");
        bool PeekKeyword(string value)
        {
            var next = _pos + 1;
            return next < _tokens.Count && _tokens[next].Type == "KEYWORD" && _tokens[next].Value == value;
        }

        bool IsKeyword(string value) => Current.Type == "KEYWORD" && Current.Value == value;
        bool CurrentIs(string type) => Current.Type == type;
        Token Current => _tokens[Math.Min(_pos, _tokens.Count - 1)];
        Token Advance() => _tokens[_pos++];
    }
}
