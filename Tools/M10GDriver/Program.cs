using System.Globalization;
using System.Text;

record Token(string Type, string Value, int Line, int Column);
record VarInfo(string Type, string Value, bool IsConst = false, bool IsRuntime = false);
record ExprResult(string Type, string Value, string Repr);
record FileValue(string Kind, string Value);
record CompareResult(bool Value, string Repr);
record RuntimeAction(string Op, string Path, string ValueKind, string Value, string Target);
record AstModel(string Program, List<(string Name, string Type, string Value)> Vars, string Title, string TitleExpr, string TitleCommand, string Message, string MessageExpr, string MessageCommand, int ExitCode, string FinalCommand, List<string> Flow, List<RuntimeAction> RuntimeActions);

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
                var backendInfo = BackendManifestInfo(inputPath);
                WriteManifest(backendManifestPath, Rel(repoRoot, outputPath), SourceFromIr(inputPath), Rel(repoRoot, inputPath), backendInfo.Backend, "windows-x64-pe", "success", backendInfo.Actions);
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
                var backendInfo = BackendManifestInfo(irPath);
                WriteManifest(manifestPath, Rel(repoRoot, outputPath), Rel(repoRoot, inputPath), Rel(repoRoot, irPath), backendInfo.Backend, "windows-x64-pe", "success", backendInfo.Actions);
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

            if (ch == '/' && IsStatementSlash(source, i))
                throw new CompileError("LEX", "L001", line, col, "Unknown character '/'.");

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
                else if (word is "program" or "let" or "be" or "title" or "message" or "text" or "show" or "set" or "to" or "exit" or "blend" or "mix" or "code" or "end" or "if" or "else" or "is" or "not" or "define" or "string" or "int" or "bool" or "var" or "called" or "rename" or "print" or "const" or "float" or "double" or "vec2" or "vec3" or "vec4" or "mat4" or "transform" or "quat" or "rect" or "circle" or "complex" or "color" or "angle" or "deg" or "rad" or "while" or "from" or "add" or "remove" or "multiply" or "by" or "divide" or "function" or "call" or "and" or "or" or "write" or "file" or "with" or "load" or "command" or "arg" or "count" or "window" or "resolution" or "resizable" or "run" or "of" or "when" or "closed" or "key" or "pressed" or "close")
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
                if (i < source.Length && source[i] == '.')
                {
                    sb.Append(source[i]);
                    i++;
                    col++;
                    if (i >= source.Length || !char.IsDigit(source[i]))
                        throw new CompileError("LEX", "L003", startLine, startCol, "Invalid decimal literal.");
                    while (i < source.Length && char.IsDigit(source[i]))
                    {
                        sb.Append(source[i]);
                        i++;
                        col++;
                    }
                    tokens.Add(new Token("DECIMAL", sb.ToString(), startLine, startCol));
                    continue;
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

            if (ch == '-')
            {
                tokens.Add(new Token("MINUS", "-", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '*')
            {
                tokens.Add(new Token("STAR", "*", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '/')
            {
                tokens.Add(new Token("SLASH", "/", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '%')
            {
                tokens.Add(new Token("PERCENT", "%", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '^')
            {
                tokens.Add(new Token("CARET", "^", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == ',')
            {
                tokens.Add(new Token("COMMA", ",", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '[')
            {
                tokens.Add(new Token("LBRACKET", "[", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == ']')
            {
                tokens.Add(new Token("RBRACKET", "]", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '(')
            {
                tokens.Add(new Token("LPAREN", "(", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == ')')
            {
                tokens.Add(new Token("RPAREN", ")", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '>')
            {
                if (i + 1 < source.Length && source[i + 1] == '=')
                {
                    tokens.Add(new Token("GTE", ">=", line, col));
                    i += 2;
                    col += 2;
                }
                else
                {
                    tokens.Add(new Token("GT", ">", line, col));
                    i++;
                    col++;
                }
                continue;
            }

            if (ch == '<')
            {
                if (i + 1 < source.Length && source[i + 1] == '=')
                {
                    tokens.Add(new Token("LTE", "<=", line, col));
                    i += 2;
                    col += 2;
                }
                else
                {
                    tokens.Add(new Token("LT", "<", line, col));
                    i++;
                    col++;
                }
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

    static bool IsStatementSlash(string source, int index)
    {
        for (var i = index - 1; i >= 0; i--)
        {
            if (source[i] is '\r' or '\n')
                return true;
            if (source[i] is not (' ' or '\t'))
                return false;
        }
        return true;
    }

    static IEnumerable<string> AstLines(AstModel ast)
    {
        yield return $"PROGRAM|{Esc(ast.Program)}";
        foreach (var v in ast.Vars)
            yield return $"LET|{Esc(v.Name)}|{Esc(v.Type)}|{Esc(v.Value)}";
        foreach (var line in ast.Flow)
            yield return line;
        foreach (var line in AstTitleLines(ast))
            yield return line;
        foreach (var line in AstMessageLines(ast))
            yield return line;
        foreach (var action in ast.RuntimeActions)
            yield return RuntimeAstLine(action);
        foreach (var line in AstFinalLines(ast))
            yield return line;
        yield return "SEMANTIC|OK";
    }

    static IEnumerable<string> AstTitleLines(AstModel ast)
    {
        if (ast.TitleCommand == "set_title_to")
            yield return $"SET_TITLE|{Esc(ast.Title)}";
        yield return $"TITLE|{Esc(ast.Title)}";
        yield return $"TITLE_EXPR|{Esc(ast.TitleExpr)}";
    }

    static IEnumerable<string> AstMessageLines(AstModel ast)
    {
        if (ast.MessageCommand == "show_message")
            yield return $"SHOW_MESSAGE|{Esc(ast.Message)}";
        yield return $"MESSAGE|{Esc(ast.Message)}";
        yield return $"MESSAGE_EXPR|{Esc(ast.MessageExpr)}";
    }

    static string RuntimeAstLine(RuntimeAction action)
        => $"RUNTIME_ACTION|op={Esc(action.Op)}|path={Esc(action.Path)}|value_kind={Esc(action.ValueKind)}|value={Esc(action.Value)}|target={Esc(action.Target)}";

    static IEnumerable<string> AstFinalLines(AstModel ast)
    {
        if (ast.FinalCommand == "blend_mix_to_code")
            yield return $"BLEND_MIX_TO_CODE|{ast.ExitCode}";
        else
            yield return $"EXIT|{ast.ExitCode}";
    }

    static IEnumerable<string> IrLines(AstModel ast, string sourcePath)
    {
        yield return "ARQIR|version=0";
        yield return $"TARGET|kind=program|name={Esc(ast.Program)}";
        yield return $"META|source={Esc(sourcePath.Replace('\\', '/'))}";
        if (ast.RuntimeActions.Count > 0)
        {
            foreach (var v in ast.Vars)
                yield return IrSymbolLine(v.Name, v.Type, v.Value);
            for (var i = 0; i < ast.RuntimeActions.Count; i++)
                yield return RuntimeIrActionLine($"act_{i}", ast.RuntimeActions[i]);
            yield return IrActionLine($"act_{ast.RuntimeActions.Count}", "exit", "code=i32_0");
            yield return IrConstLine("i32_0", "int", ast.ExitCode.ToString());
            yield return $"ENTRY|actions={string.Join(",", Enumerable.Range(0, ast.RuntimeActions.Count + 1).Select(i => $"act_{i}"))}";
            yield return "END";
            yield break;
        }
        yield return IrConstLine("str_0", "text", ast.Title);
        yield return IrConstLine("str_1", "text", ast.Message);
        yield return IrConstLine("i32_0", "int", ast.ExitCode.ToString());
        if (ast.MessageCommand == "print")
            yield return IrActionLine("act_0", "print_stdout", "text=str_1");
        else
            yield return IrActionLine("act_0", "show_message", "title=str_0|text=str_1");
        yield return IrActionLine("act_1", "exit", "code=i32_0");
        yield return "ENTRY|actions=act_0,act_1";
        yield return "END";
    }

    static string IrConstLine(string id, string type, string value) => $"CONST|id={id}|type={type}|value={Esc(value)}";
    static string IrSymbolLine(string name, string type, string value) => $"SYMBOL|name={Esc(name)}|type={Esc(type)}|value={Esc(value)}";
    static string IrActionLine(string id, string op, string fields) => $"ACTION|id={id}|op={op}|{fields}";
    static string RuntimeIrActionLine(string id, RuntimeAction action)
    {
        var fields = $"path={Esc(action.Path)}|value_kind={Esc(action.ValueKind)}|value={Esc(action.Value)}|target={Esc(action.Target)}";
        return IrActionLine(id, action.Op, fields);
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

        if (HasWindowActions(ir))
        {
            if (HasFileIoActions(ir))
                throw new CompileError("BACKEND", "B005", 0, 0, "Mixing file I/O and window commands is not supported.");
            
            var windowPe = BuildWindowPe(ir);
            var windowTmpPath = outputPath + ".tmp";
            File.WriteAllBytes(windowTmpPath, windowPe);
            File.Move(windowTmpPath, outputPath, true);
            return;
        }

        if (HasFileIoActions(ir))
        {
            var fileIoPe = BuildFileIoPe(ir);
            var fileIoTmpPath = outputPath + ".tmp";
            File.WriteAllBytes(fileIoTmpPath, fileIoPe);
            File.Move(fileIoTmpPath, outputPath, true);
            return;
        }

        if (!ir.Actions.TryGetValue("act_0", out var first) ||
            !first.TryGetValue("op", out var firstOp))
            throw new CompileError("BACKEND", "B001", 0, 0, "Missing supported first action.");

        if (!ir.Actions.TryGetValue("act_1", out var exit) ||
            !exit.TryGetValue("op", out var exitOp) ||
            exitOp != "exit" ||
            !exit.TryGetValue("code", out var codeId) ||
            !ir.Consts.TryGetValue(codeId, out var codeConst) ||
            codeConst.Type != "int" ||
            codeConst.Value != "0")
            throw new CompileError("BACKEND", "B001", 0, 0, "Only exit code 0 is supported by this backend.");

        if (firstOp == "print_stdout")
        {
            if (!first.TryGetValue("text", out var stdoutTextId) ||
                !ir.Consts.TryGetValue(stdoutTextId, out var stdoutTextConst) ||
                stdoutTextConst.Type != "text")
                throw new CompileError("BACKEND", "B001", 0, 0, "Invalid print_stdout constants.");

            var stdoutText = stdoutTextConst.Value;
            if (stdoutText.Length > 0 && !stdoutText.EndsWith('\n'))
                stdoutText += "\n";
            var stdoutPe = BuildStdoutPe(stdoutText);
            var stdoutTmpPath = outputPath + ".tmp";
            File.WriteAllBytes(stdoutTmpPath, stdoutPe);
            File.Move(stdoutTmpPath, outputPath, true);
            return;
        }

        if (firstOp != "show_message")
            throw new CompileError("BACKEND", "B001", 0, 0, $"Unsupported first action: {firstOp}.");

        if (!first.TryGetValue("title", out var titleId) ||
            !first.TryGetValue("text", out var textId) ||
            !ir.Consts.TryGetValue(titleId, out var titleConst) ||
            !ir.Consts.TryGetValue(textId, out var textConst) ||
            titleConst.Type != "text" ||
            textConst.Type != "text")
            throw new CompileError("BACKEND", "B001", 0, 0, "Invalid show_message constants.");

        var pe = BuildMessageBoxPe(textConst.Value, titleConst.Value);

        var tmpPath = outputPath + ".tmp";
        File.WriteAllBytes(tmpPath, pe);
        File.Move(tmpPath, outputPath, true);
    }

    static byte[] BuildMessageBoxPe(string text, string title)
    {
        const int sectionRaw = 0x200;
        const int sectionRva = 0x1000;
        const int sectionSize = 0x4000;
        const int importRva = 0x1300;
        const int userIltRva = 0x1380;
        const int userIatRva = 0x1390;
        const int kernelIltRva = 0x13a0;
        const int kernelIatRva = 0x13b0;
        const int userNameRva = 0x13c0;
        const int kernelNameRva = 0x13d0;
        const int messageBoxNameRva = 0x13f0;
        const int exitProcessNameRva = 0x1410;
        const int messageRva = 0x1800;
        const int titleRva = 0x3000;
        const int maxMessageBytes = 0x400;
        const int maxTitleBytes = 0x100;

        var messageBytes = Encoding.Unicode.GetBytes(text + "\0");
        var titleBytes = Encoding.Unicode.GetBytes(title + "\0");
        if (messageBytes.Length > maxMessageBytes)
            throw new CompileError("BACKEND", "B003", 0, 0, $"visual message text too long for M15B backend: {messageBytes.Length} bytes.");
        if (titleBytes.Length > maxTitleBytes)
            throw new CompileError("BACKEND", "B003", 0, 0, $"visual title too long for M15B backend: {titleBytes.Length} bytes.");

        var pe = new byte[sectionRaw + sectionSize];
        WriteAscii(pe, 0, "MZ");
        WriteUInt32(pe, 0x3c, 0x80);

        var peOffset = 0x80;
        WriteAscii(pe, peOffset, "PE\0\0");
        var coff = peOffset + 4;
        WriteUInt16(pe, coff, 0x8664);
        WriteUInt16(pe, coff + 2, 1);
        WriteUInt16(pe, coff + 16, 0xF0);
        WriteUInt16(pe, coff + 18, 0x22);

        var opt = coff + 20;
        WriteUInt16(pe, opt, 0x20b);
        pe[opt + 2] = 14;
        WriteUInt32(pe, opt + 4, sectionSize);
        WriteUInt32(pe, opt + 16, sectionRva);
        WriteUInt32(pe, opt + 20, sectionRva);
        WriteUInt64(pe, opt + 24, 0x140000000);
        WriteUInt32(pe, opt + 32, 0x1000);
        WriteUInt32(pe, opt + 36, 0x200);
        WriteUInt16(pe, opt + 40, 6);
        WriteUInt16(pe, opt + 48, 6);
        WriteUInt32(pe, opt + 56, 0x5000);
        WriteUInt32(pe, opt + 60, 0x200);
        WriteUInt16(pe, opt + 68, 2);
        WriteUInt64(pe, opt + 72, 0x100000);
        WriteUInt64(pe, opt + 80, 0x1000);
        WriteUInt64(pe, opt + 88, 0x100000);
        WriteUInt64(pe, opt + 96, 0x1000);
        WriteUInt32(pe, opt + 108, 16);
        WriteUInt32(pe, opt + 120, importRva);
        WriteUInt32(pe, opt + 124, 0x300);

        var section = opt + 0xF0;
        WriteAscii(pe, section, ".text\0\0\0");
        WriteUInt32(pe, section + 8, sectionSize);
        WriteUInt32(pe, section + 12, sectionRva);
        WriteUInt32(pe, section + 16, sectionSize);
        WriteUInt32(pe, section + 20, sectionRaw);
        WriteUInt32(pe, section + 36, 0xE0000020);

        var code = new List<byte>();
        void Emit(params byte[] bytes) => code.AddRange(bytes);
        void EmitUInt32(uint value) => code.AddRange(BitConverter.GetBytes(value));
        void CallIat(int rva)
        {
            var nextRva = sectionRva + code.Count + 6;
            Emit(0xff, 0x15);
            EmitUInt32(unchecked((uint)(rva - nextRva)));
        }
        void Lea(byte[] prefix, int targetRva, int instructionLength)
        {
            var nextRva = sectionRva + code.Count + instructionLength;
            Emit(prefix);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }

        Emit(0x48, 0x83, 0xec, 0x28);
        Emit(0x31, 0xC9);
        Lea(new byte[] { 0x48, 0x8D, 0x15 }, messageRva, 7);
        Lea(new byte[] { 0x4C, 0x8D, 0x05 }, titleRva, 7);
        Emit(0x45, 0x31, 0xC9);
        CallIat(userIatRva);
        Emit(0x31, 0xC9);
        CallIat(kernelIatRva);
        code.CopyTo(pe, sectionRaw);

        var importRaw = RvaToRaw(importRva);
        WriteUInt32(pe, importRaw, userIltRva);
        WriteUInt32(pe, importRaw + 12, userNameRva);
        WriteUInt32(pe, importRaw + 16, userIatRva);
        WriteUInt32(pe, importRaw + 20, kernelIltRva);
        WriteUInt32(pe, importRaw + 32, kernelNameRva);
        WriteUInt32(pe, importRaw + 36, kernelIatRva);

        AddImport(pe, userIltRva, userIatRva, 0, messageBoxNameRva, "MessageBoxW");
        AddImport(pe, kernelIltRva, kernelIatRva, 0, exitProcessNameRva, "ExitProcess");
        WriteAscii(pe, RvaToRaw(userNameRva), "user32.dll\0");
        WriteAscii(pe, RvaToRaw(kernelNameRva), "kernel32.dll\0");
        Array.Copy(messageBytes, 0, pe, RvaToRaw(messageRva), messageBytes.Length);
        Array.Copy(titleBytes, 0, pe, RvaToRaw(titleRva), titleBytes.Length);
        return pe;

        static int RvaToRaw(int rva) => sectionRaw + (rva - sectionRva);
    }

    static byte[] BuildWindowPe(IrModel ir)
    {
        const int sectionRaw = 0x200;
        const int sectionRva = 0x1000;
        const int sectionSize = 0x5000;
        const int importRva = 0x1800;
        const int kernelIltRva = 0x1840;
        const int userIltRva = 0x1860;
        const int kernelIatRva = 0x18C0;
        const int userIatRva = 0x18E0;
        const int kernelDllNameRva = 0x1940;
        const int userDllNameRva = 0x1960;
        const int importNameCursorStart = 0x1980;
        const int dataStartRva = 0x2000;

        var actions = OrderedActionMaps(ir);
        if (actions.Count == 0 || actions[^1].GetValueOrDefault("op") != "exit")
            throw new CompileError("BACKEND", "B001", 0, 0, "Window backend requires final exit action.");

        if (actions.Any(a => a.GetValueOrDefault("op") == "print_stdout"))
            throw new CompileError("BACKEND", "B006", 0, 0, "Mixing window commands with print_stdout is not supported in M15F.");

        var pe = new byte[sectionRaw + sectionSize];
        WritePeHeader(pe, sectionSize, importRva, 0x600, subsystem: 2); // Windows GUI

        var dataCursor = dataStartRva;
        
        int AddUtf16(string text)
        {
            var bytes = Encoding.Unicode.GetBytes(text + "\0");
            var rva = dataCursor;
            Array.Copy(bytes, 0, pe, RvaToRaw(rva), bytes.Length);
            dataCursor += bytes.Length;
            return rva;
        }

        var classNameRva = AddUtf16("ArqenWindow");

        string windowTitle = "Arqen Window";
        int width = 1280;
        int height = 720;
        bool resizable = true;
        bool hasShow = false;
        bool hasRun = false;

        var closedHandlers = new Dictionary<string, List<Dictionary<string, string>>>(StringComparer.Ordinal);
        var keyHandlers = new Dictionary<string, List<Dictionary<string, string>>>(StringComparer.Ordinal);
        List<Dictionary<string, string>>? currentEventBlock = null;

        foreach (var action in actions)
        {
            var op = action.GetValueOrDefault("op");
            if (op == "event_window_closed")
            {
                currentEventBlock = new List<Dictionary<string, string>>();
                closedHandlers[action.GetValueOrDefault("target") ?? ""] = currentEventBlock;
            }
            else if (op == "event_key_pressed")
            {
                currentEventBlock = new List<Dictionary<string, string>>();
                keyHandlers[action.GetValueOrDefault("value") ?? ""] = currentEventBlock;
            }
            else if (op == "event_end")
            {
                currentEventBlock = null;
            }
            else if (currentEventBlock != null)
            {
                currentEventBlock.Add(action);
            }
            else
            {
                if (op == "window_set_title") windowTitle = action.GetValueOrDefault("value") ?? windowTitle;
                if (op == "window_set_resolution")
                {
                    var val = action.GetValueOrDefault("value") ?? "";
                    var parts = val.Split('x');
                    if (parts.Length == 2 && int.TryParse(parts[0], out var w) && int.TryParse(parts[1], out var h))
                    {
                        width = w;
                        height = h;
                    }
                }
                if (op == "window_set_resizable") resizable = (action.GetValueOrDefault("value") ?? "") == "true";
                if (op == "window_show") hasShow = true;
                if (op == "window_run") hasRun = true;
            }
        }

        var titleRva = AddUtf16(windowTitle);

        var kernelImports = new[] { "ExitProcess", "GetModuleHandleW" };
        var userImports = new[] { "RegisterClassW", "CreateWindowExW", "ShowWindow", "UpdateWindow", "GetMessageW", "TranslateMessage", "DispatchMessageW", "DefWindowProcW", "PostQuitMessage", "DestroyWindow", "PostMessageW" };
        
        var importNameCursor = importNameCursorStart;
        for (var i = 0; i < kernelImports.Length; i++)
        {
            AddImport(pe, kernelIltRva, kernelIatRva, i, importNameCursor, kernelImports[i]);
            importNameCursor += 0x20;
        }
        for (var i = 0; i < userImports.Length; i++)
        {
            AddImport(pe, userIltRva, userIatRva, i, importNameCursor, userImports[i]);
            importNameCursor += 0x20;
        }

        Encoding.ASCII.GetBytes("KERNEL32.dll\0").CopyTo(pe, RvaToRaw(kernelDllNameRva));
        Encoding.ASCII.GetBytes("USER32.dll\0").CopyTo(pe, RvaToRaw(userDllNameRva));

        // ILT / IAT table entries for KERNEL32
        pe[RvaToRaw(importRva)] = (byte)(kernelIltRva & 0xff); pe[RvaToRaw(importRva) + 1] = (byte)((kernelIltRva >> 8) & 0xff);
        pe[RvaToRaw(importRva) + 12] = (byte)(kernelDllNameRva & 0xff); pe[RvaToRaw(importRva) + 13] = (byte)((kernelDllNameRva >> 8) & 0xff);
        pe[RvaToRaw(importRva) + 16] = (byte)(kernelIatRva & 0xff); pe[RvaToRaw(importRva) + 17] = (byte)((kernelIatRva >> 8) & 0xff);
        
        // ILT / IAT table entries for USER32
        var userDescRva = importRva + 20;
        pe[RvaToRaw(userDescRva)] = (byte)(userIltRva & 0xff); pe[RvaToRaw(userDescRva) + 1] = (byte)((userIltRva >> 8) & 0xff);
        pe[RvaToRaw(userDescRva) + 12] = (byte)(userDllNameRva & 0xff); pe[RvaToRaw(userDescRva) + 13] = (byte)((userDllNameRva >> 8) & 0xff);
        pe[RvaToRaw(userDescRva) + 16] = (byte)(userIatRva & 0xff); pe[RvaToRaw(userDescRva) + 17] = (byte)((userIatRva >> 8) & 0xff);

        var entryRva = sectionRva + 0x100;
        var codeStart = entryRva;
        var code = new List<byte>();

        void Emit(params byte[] b) => code.AddRange(b);
        int EmitShortJump(byte opcode) { Emit(opcode, 0); return code.Count - 1; }
        void PatchShort(int jumpOffset, int targetRva) { code[jumpOffset] = (byte)((targetRva - (codeStart + jumpOffset + 1)) & 0xFF); }
        void CallIat(int rva)
        {
            Emit(0xFF, 0x15);
            var rip = codeStart + code.Count + 4;
            var offset = rva - rip;
            Emit((byte)(offset & 0xFF), (byte)((offset >> 8) & 0xFF), (byte)((offset >> 16) & 0xFF), (byte)((offset >> 24) & 0xFF));
        }

        var wndProcRva = sectionRva + 0x300;
        var wndProcCode = new List<byte>();
        void EmitProc(params byte[] b) => wndProcCode.AddRange(b);
        void CallProcIat(int rva)
        {
            EmitProc(0xFF, 0x15);
            var rip = wndProcRva + wndProcCode.Count + 4;
            var offset = rva - rip;
            EmitProc((byte)(offset & 0xFF), (byte)((offset >> 8) & 0xFF), (byte)((offset >> 16) & 0xFF), (byte)((offset >> 24) & 0xFF));
        }

        int EmitShortJumpProc(byte op)
        {
            EmitProc(op, 0x00);
            return wndProcCode.Count - 1;
        }

        void PatchShortProc(int offset)
        {
            int diff = wndProcCode.Count - (offset + 1);
            if (diff > 127) throw new CompileError("BACKEND", "B007", 0, 0, "Event block too large for short jump.");
            wndProcCode[offset] = (byte)diff;
        }

        EmitProc(0x48, 0x89, 0x4C, 0x24, 0x08); // rcx -> shadow
        EmitProc(0x89, 0x54, 0x24, 0x10);       // rdx -> shadow
        EmitProc(0x4C, 0x89, 0x44, 0x24, 0x18); // r8 -> shadow
        EmitProc(0x4C, 0x89, 0x4C, 0x24, 0x20); // r9 -> shadow
        EmitProc(0x48, 0x83, 0xEC, 0x28);       // sub rsp, 40

        // WM_DESTROY (2)
        EmitProc(0x81, 0xFA, 0x02, 0x00, 0x00, 0x00); // cmp edx, 2
        var jneDestroy = EmitShortJumpProc(0x75);
        EmitProc(0x31, 0xC9); // xor ecx, ecx
        CallProcIat(userIatRva + 8 * 8); // PostQuitMessage
        EmitProc(0x31, 0xC0); // xor eax, eax
        EmitProc(0x48, 0x83, 0xC4, 0x28); // add rsp, 40
        EmitProc(0xC3); // ret
        PatchShortProc(jneDestroy);

        // WM_CLOSE (16)
        if (closedHandlers.TryGetValue("Window", out var cActions))
        {
            EmitProc(0x81, 0xFA, 0x10, 0x00, 0x00, 0x00); // cmp edx, 16
            var jneClose = EmitShortJumpProc(0x75);
            bool explicitlyClosed = false;
            foreach (var act in cActions)
            {
                if (act.GetValueOrDefault("op") == "window_close")
                {
                    EmitProc(0x48, 0x8B, 0x4C, 0x24, 0x30); // mov rcx, [rsp+48] (hWnd)
                    CallProcIat(userIatRva + 9 * 8); // DestroyWindow
                    explicitlyClosed = true;
                }
            }
            if (explicitlyClosed)
            {
                EmitProc(0x31, 0xC0); // xor eax, eax
                EmitProc(0x48, 0x83, 0xC4, 0x28); // add rsp, 40
                EmitProc(0xC3); // ret
            }
            PatchShortProc(jneClose);
        }

        // WM_KEYDOWN (256 / 0x0100)
        if (keyHandlers.TryGetValue("Escape", out var kActions))
        {
            EmitProc(0x81, 0xFA, 0x00, 0x01, 0x00, 0x00); // cmp edx, 0x0100
            var jneKey = EmitShortJumpProc(0x75);
            EmitProc(0x49, 0x81, 0xF8, 0x1B, 0x00, 0x00, 0x00); // cmp r8, 0x1B (VK_ESCAPE)
            var jneEsc = EmitShortJumpProc(0x75);
            
            bool explicitlyClosed = false;
            foreach (var act in kActions)
            {
                if (act.GetValueOrDefault("op") == "window_close")
                {
                    EmitProc(0x48, 0x8B, 0x4C, 0x24, 0x30); // mov rcx, [rsp+48] (hWnd)
                    EmitProc(0xBA, 0x10, 0x00, 0x00, 0x00); // mov edx, 0x0010 (WM_CLOSE)
                    EmitProc(0x45, 0x31, 0xC0); // xor r8d, r8d
                    EmitProc(0x45, 0x31, 0xC9); // xor r9d, r9d
                    CallProcIat(userIatRva + 10 * 8); // PostMessageW
                    explicitlyClosed = true;
                }
            }
            if (explicitlyClosed)
            {
                EmitProc(0x31, 0xC0); // xor eax, eax
                EmitProc(0x48, 0x83, 0xC4, 0x28); // add rsp, 40
                EmitProc(0xC3); // ret
            }
            PatchShortProc(jneEsc);
            PatchShortProc(jneKey);
        }

        // DefWindowProcW
        EmitProc(0x48, 0x8B, 0x4C, 0x24, 0x30); // mov rcx, [rsp+48]
        EmitProc(0x8B, 0x54, 0x24, 0x38); // mov edx, [rsp+56]
        EmitProc(0x4C, 0x8B, 0x44, 0x24, 0x40); // mov r8, [rsp+64]
        EmitProc(0x4C, 0x8B, 0x4C, 0x24, 0x48); // mov r9, [rsp+72]
        CallProcIat(userIatRva + 7 * 8); // DefWindowProcW
        EmitProc(0x48, 0x83, 0xC4, 0x28); // add rsp, 40
        EmitProc(0xC3); // ret

        Array.Copy(wndProcCode.ToArray(), 0, pe, RvaToRaw(wndProcRva), wndProcCode.Count);

        Emit(0x48, 0x83, 0xEC, 0x68); // sub rsp, 104
        Emit(0x31, 0xC9); // xor ecx, ecx
        CallIat(kernelIatRva + 1 * 8); // GetModuleHandleW
        Emit(0x48, 0x89, 0xC3); // mov rbx, rax (hInstance)

        Emit(0x48, 0x8D, 0x4C, 0x24, 0x20); // mov rcx, rsp+32
        Emit(0x31, 0xD2); // xor edx, edx
        Emit(0x41, 0xB8, 0x48, 0x00, 0x00, 0x00); // mov r8d, 72 (sizeof WNDCLASSW)
        // memset is complex, let's just zero it directly
        for(int j=0; j<8; j++) Emit(0x48, 0xC7, 0x44, 0x24, (byte)(0x20 + j*8), 0x00, 0x00, 0x00, 0x00);
        
        Emit(0x48, 0x8D, 0x05);
        int wndProcOffset = wndProcRva - (codeStart + code.Count + 4);
        Emit((byte)(wndProcOffset & 0xFF), (byte)((wndProcOffset >> 8) & 0xFF), (byte)((wndProcOffset >> 16) & 0xFF), (byte)((wndProcOffset >> 24) & 0xFF));
        Emit(0x48, 0x89, 0x44, 0x24, 0x28); // lpfnWndProc = wndProcRva
        
        Emit(0x48, 0x89, 0x5C, 0x24, 0x38); // hInstance = rbx
        
        Emit(0x48, 0x8D, 0x05);
        int classNameOffset = classNameRva - (codeStart + code.Count + 4);
        Emit((byte)(classNameOffset & 0xFF), (byte)((classNameOffset >> 8) & 0xFF), (byte)((classNameOffset >> 16) & 0xFF), (byte)((classNameOffset >> 24) & 0xFF));
        Emit(0x48, 0x89, 0x44, 0x24, 0x60); // lpszClassName = classNameRva
        
        Emit(0x48, 0x8D, 0x4C, 0x24, 0x20); // rcx = &wc
        CallIat(userIatRva); // RegisterClassW
        
        Emit(0x48, 0xC7, 0xC1, 0x00, 0x00, 0x00, 0x00); // rcx = 0
        Emit(0x48, 0x8D, 0x15); // rdx = classNameRva
        classNameOffset = classNameRva - (codeStart + code.Count + 4);
        Emit((byte)(classNameOffset & 0xFF), (byte)((classNameOffset >> 8) & 0xFF), (byte)((classNameOffset >> 16) & 0xFF), (byte)((classNameOffset >> 24) & 0xFF));
        Emit(0x4C, 0x8D, 0x05); // r8 = titleRva
        int titleOffset = titleRva - (codeStart + code.Count + 4);
        Emit((byte)(titleOffset & 0xFF), (byte)((titleOffset >> 8) & 0xFF), (byte)((titleOffset >> 16) & 0xFF), (byte)((titleOffset >> 24) & 0xFF));
        
        // WS_VISIBLE=0x10000000, WS_OVERLAPPEDWINDOW=0x00CF0000, WS_CAPTION=0x00C00000, WS_SYSMENU=0x00080000, WS_MINIMIZEBOX=0x00020000
        uint style = resizable ? 0x10CF0000u : 0x10CA0000u;
        Emit(0x41, 0xB9, (byte)(style & 0xFF), (byte)((style >> 8) & 0xFF), (byte)((style >> 16) & 0xFF), (byte)((style >> 24) & 0xFF)); // r9 = style
        
        Emit(0xC7, 0x44, 0x24, 0x20, 0x00, 0x00, 0x00, 0x80); // CW_USEDEFAULT
        Emit(0xC7, 0x44, 0x24, 0x28, 0x00, 0x00, 0x00, 0x80); // CW_USEDEFAULT
        Emit(0xC7, 0x44, 0x24, 0x30, (byte)(width & 0xFF), (byte)((width >> 8) & 0xFF), 0x00, 0x00);
        Emit(0xC7, 0x44, 0x24, 0x38, (byte)(height & 0xFF), (byte)((height >> 8) & 0xFF), 0x00, 0x00);
        Emit(0x48, 0xC7, 0x44, 0x24, 0x40, 0x00, 0x00, 0x00, 0x00); // hWndParent
        Emit(0x48, 0xC7, 0x44, 0x24, 0x48, 0x00, 0x00, 0x00, 0x00); // hMenu
        Emit(0x48, 0x89, 0x5C, 0x24, 0x50); // hInstance
        Emit(0x48, 0xC7, 0x44, 0x24, 0x58, 0x00, 0x00, 0x00, 0x00); // lpParam
        
        CallIat(userIatRva + 1 * 8); // CreateWindowExW
        Emit(0x48, 0x89, 0xC3); // rbx = hWnd
        
        if (hasShow)
        {
            Emit(0x48, 0x89, 0xD9); // rcx = hWnd
            Emit(0xBA, 0x01, 0x00, 0x00, 0x00); // rdx = SW_SHOWNORMAL
            CallIat(userIatRva + 2 * 8); // ShowWindow
            Emit(0x48, 0x89, 0xD9); // rcx = hWnd
            CallIat(userIatRva + 3 * 8); // UpdateWindow
        }

        if (hasRun && hasShow)
        {
            var msgLoopStart = code.Count;
            Emit(0x48, 0x8D, 0x4C, 0x24, 0x20); // rcx = &msg
            Emit(0x31, 0xD2); // rdx = 0
            Emit(0x45, 0x31, 0xC0); // r8 = 0
            Emit(0x45, 0x31, 0xC9); // r9 = 0
            CallIat(userIatRva + 4 * 8); // GetMessageW
            Emit(0x85, 0xC0); // test eax, eax
            var jzExit = EmitShortJump(0x74); // jz exit
            Emit(0x48, 0x8D, 0x4C, 0x24, 0x20); // rcx = &msg
            CallIat(userIatRva + 5 * 8); // TranslateMessage
            Emit(0x48, 0x8D, 0x4C, 0x24, 0x20); // rcx = &msg
            CallIat(userIatRva + 6 * 8); // DispatchMessageW
            var jmpLoop = EmitShortJump(0xEB); // jmp loop
            PatchShort(jmpLoop, sectionRva + 0x100 + msgLoopStart);
            PatchShort(jzExit, sectionRva + 0x100 + code.Count);
        }

        Emit(0x31, 0xC9); // xor ecx, ecx
        CallIat(kernelIatRva); // ExitProcess

        Array.Copy(code.ToArray(), 0, pe, RvaToRaw(entryRva), code.Count);
        pe[0x128] = (byte)(entryRva & 0xff);
        pe[0x129] = (byte)((entryRva >> 8) & 0xff);
        pe[0x12A] = (byte)((entryRva >> 16) & 0xff);
        pe[0x12B] = (byte)((entryRva >> 24) & 0xff);

        return pe;

        int RvaToRaw(int rva) => sectionRaw + (rva - sectionRva);
    }

    static byte[] BuildFileIoPe(IrModel ir)
    {
        const int sectionRaw = 0x200;
        const int sectionRva = 0x1000;
        const int sectionSize = 0x100000;
        const int importRva = 0x40000;
        const int iltRva = 0x40100;
        const int iatRva = 0x40180;
        const int kernelDllNameRva = 0x40280;
        const int dataStartRva = 0x41000;
        const int slotLenStartRva = 0xE0000;
        const int slotStartRva = 0xE1000;
        const int runtimeSlotBytes = 0x1000;
        const int bytesWrittenRva = slotLenStartRva - 8;

        var actions = OrderedActionMaps(ir);
        if (actions.Count == 0 || actions[^1].GetValueOrDefault("op") != "exit")
            throw new CompileError("BACKEND", "B001", 0, 0, "File I/O backend requires final exit action.");

        var pe = new byte[sectionRaw + sectionSize];
        WritePeHeader(pe, sectionSize, importRva, 0x600, subsystem: 3);

        var slotNames = actions
            .Where(a => a.GetValueOrDefault("value_kind") == "slot" || a.GetValueOrDefault("op") == "file_load" || a.GetValueOrDefault("op") == "print_runtime_slot" || a.GetValueOrDefault("op") == "command_arg_count" || a.GetValueOrDefault("op") == "command_arg_index")
            .Select(a => a.GetValueOrDefault("target") != "" ? a.GetValueOrDefault("target")! : a.GetValueOrDefault("value")!)
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Distinct(StringComparer.Ordinal)
            .ToList();
        var slots = new Dictionary<string, (int BufferRva, int LenRva)>(StringComparer.Ordinal);
        var maxRuntimeSlots = (sectionRva + sectionSize - slotStartRva) / runtimeSlotBytes;
        if (slotNames.Count > maxRuntimeSlots)
            throw new CompileError("BACKEND", "B001", 0, 0, $"Too many runtime string slots for file I/O backend: {slotNames.Count} > {maxRuntimeSlots}.");
        for (var i = 0; i < slotNames.Count; i++)
            slots[slotNames[i]] = (slotStartRva + i * runtimeSlotBytes, slotLenStartRva + i * 8);

        var dataCursor = dataStartRva;
        var pathRvas = new Dictionary<string, int>(StringComparer.Ordinal);
        var valueRvas = new Dictionary<string, (int Rva, int Length)>(StringComparer.Ordinal);
        var newlineRva = AddUtf8("\n");

        foreach (var action in actions)
        {
            var op = action.GetValueOrDefault("op");
            if (op is "file_write" or "file_append" or "file_load")
                GetPath(action.GetValueOrDefault("path") ?? "");
            if (action.GetValueOrDefault("value_kind") == "static")
                GetValue(action.GetValueOrDefault("value") ?? "");
            if (op == "print_stdout")
            {
                var textId = action["text"];
                var text = ir.Consts[textId].Value;
                if (text.Length > 0 && !text.EndsWith('\n')) text += "\n";
                var messageBytes = Encoding.UTF8.GetBytes(text);
                if (messageBytes.Length > 0x900)
                    throw new CompileError("BACKEND", "B004", 0, 0, $"stdout text too long for M15 stdout backend: {messageBytes.Length} bytes.");
                GetValue(text);
            }
        }

        var importNameCursor = kernelDllNameRva + 0x40;
        var kernelImports = new[] { "CreateFileW", "WriteFile", "ReadFile", "CloseHandle", "SetFilePointer", "GetStdHandle", "GetCommandLineW", "ExitProcess" };
        for (var i = 0; i < kernelImports.Length; i++)
        {
            AddImport(pe, iltRva, iatRva, i, importNameCursor, kernelImports[i]);
            importNameCursor += 0x20;
        }
        WriteAscii(pe, RvaToRaw(kernelDllNameRva), "kernel32.dll\0");
        var importRaw = RvaToRaw(importRva);
        WriteUInt32(pe, importRaw, iltRva);
        WriteUInt32(pe, importRaw + 12, kernelDllNameRva);
        WriteUInt32(pe, importRaw + 16, iatRva);

        var code = new List<byte>();
        var failJumps = new List<int>();
        void Emit(params byte[] bytes) => code.AddRange(bytes);
        void EmitUInt32(uint value) => code.AddRange(BitConverter.GetBytes(value));
        void CallIat(int index)
        {
            var rva = iatRva + index * 8;
            var nextRva = sectionRva + code.Count + 6;
            Emit(0xff, 0x15);
            EmitUInt32(unchecked((uint)(rva - nextRva)));
        }
        void Lea(byte[] prefix, int targetRva, int instructionLength)
        {
            var nextRva = sectionRva + code.Count + instructionLength;
            Emit(prefix);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        void MovR8dFromMem(int targetRva)
        {
            var nextRva = sectionRva + code.Count + 7;
            Emit(0x44, 0x8B, 0x05);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        void StoreR8dToMem(int targetRva)
        {
            var nextRva = sectionRva + code.Count + 7;
            Emit(0x44, 0x89, 0x05);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        void StoreDwordMem(int targetRva, uint value)
        {
            var nextRva = sectionRva + code.Count + 10;
            Emit(0xC7, 0x05);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
            EmitUInt32(value);
        }
        void StoreByteFromAl(int targetRva)
        {
            var nextRva = sectionRva + code.Count + 6;
            Emit(0x88, 0x05);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        void StoreByteFromBl(int targetRva)
        {
            var nextRva = sectionRva + code.Count + 6;
            Emit(0x88, 0x1D);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        void StoreByteFromDl(int targetRva)
        {
            var nextRva = sectionRva + code.Count + 6;
            Emit(0x88, 0x15);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }
        int EmitNearJump2(byte op1, byte op2)
        {
            Emit(op1, op2);
            var pos = code.Count;
            EmitUInt32(0);
            return pos;
        }
        int EmitShortJump(byte op)
        {
            Emit(op);
            var pos = code.Count;
            Emit(0);
            return pos;
        }
        int EmitNearJump(byte op)
        {
            Emit(op);
            var pos = code.Count;
            EmitUInt32(0);
            return pos;
        }
        void PatchRel32(int offsetPos, int targetRva)
        {
            var nextRva = sectionRva + offsetPos + 4;
            var bytes = BitConverter.GetBytes(targetRva - nextRva);
            for (var i = 0; i < 4; i++)
                code[offsetPos + i] = bytes[i];
        }
        void PatchShort(int offsetPos, int targetRva)
        {
            var nextRva = sectionRva + offsetPos + 1;
            var rel = targetRva - nextRva;
            if (rel < sbyte.MinValue || rel > sbyte.MaxValue)
                throw new CompileError("BACKEND", "B001", 0, 0, "Internal jump too far.");
            code[offsetPos] = unchecked((byte)(sbyte)rel);
        }
        void JeFail()
        {
            Emit(0x0F, 0x84);
            failJumps.Add(code.Count);
            EmitUInt32(0);
        }
        void CheckRaxInvalidHandle()
        {
            Emit(0x48, 0x83, 0xF8, 0xFF);
            JeFail();
        }
        void CheckEaxZero()
        {
            Emit(0x85, 0xC0);
            JeFail();
        }
        void CheckRaxZero()
        {
            Emit(0x48, 0x85, 0xC0);
            JeFail();
        }
        void StoreStack32(byte offset, uint value)
        {
            Emit(0x48, 0xC7, 0x44, 0x24, offset);
            EmitUInt32(value);
        }
        void OpenFile(string path, uint access, uint disposition)
        {
            Lea(new byte[] { 0x48, 0x8D, 0x0D }, GetPath(path), 7);
            Emit(0xBA); EmitUInt32(access);
            Emit(0x45, 0x31, 0xC0);
            Emit(0x45, 0x31, 0xC9);
            StoreStack32(0x20, disposition);
            StoreStack32(0x28, 0x80);
            StoreStack32(0x30, 0);
            CallIat(0);
            CheckRaxInvalidHandle();
            Emit(0x48, 0x89, 0xC3);
        }
        void WriteHandleFromStatic(string value)
        {
            var data = GetValue(value);
            Emit(0x48, 0x89, 0xD9);
            Lea(new byte[] { 0x48, 0x8D, 0x15 }, data.Rva, 7);
            Emit(0x41, 0xB8); EmitUInt32((uint)data.Length);
            Lea(new byte[] { 0x4C, 0x8D, 0x0D }, bytesWrittenRva, 7);
            StoreStack32(0x20, 0);
            CallIat(1);
            CheckEaxZero();
        }
        void WriteHandleFromSlot(string slot)
        {
            var s = slots[slot];
            Emit(0x48, 0x89, 0xD9);
            Lea(new byte[] { 0x48, 0x8D, 0x15 }, s.BufferRva, 7);
            MovR8dFromMem(s.LenRva);
            Lea(new byte[] { 0x4C, 0x8D, 0x0D }, bytesWrittenRva, 7);
            StoreStack32(0x20, 0);
            CallIat(1);
            CheckEaxZero();
        }
        void SkipCommandLineSpaces()
        {
            var loopRva = sectionRva + code.Count;
            Emit(0x66, 0x83, 0x3E, 0x20);
            var done = EmitNearJump2(0x0F, 0x85);
            Emit(0x48, 0x83, 0xC6, 0x02);
            var back = EmitNearJump(0xE9);
            var doneRva = sectionRva + code.Count;
            PatchRel32(done, doneRva);
            PatchRel32(back, loopRva);
        }
        void SkipCommandLineArg()
        {
            SkipCommandLineSpaces();
            Emit(0x66, 0x83, 0x3E, 0x00);
            var doneAtZero = EmitNearJump2(0x0F, 0x84);
            Emit(0x66, 0x83, 0x3E, 0x22);
            var unquoted = EmitNearJump2(0x0F, 0x85);
            Emit(0x48, 0x83, 0xC6, 0x02);
            var quotedLoopRva = sectionRva + code.Count;
            Emit(0x66, 0x83, 0x3E, 0x00);
            var quotedDoneZero = EmitNearJump2(0x0F, 0x84);
            Emit(0x66, 0x83, 0x3E, 0x22);
            var quotedEnd = EmitNearJump2(0x0F, 0x84);
            Emit(0x48, 0x83, 0xC6, 0x02);
            var quotedBack = EmitNearJump(0xE9);
            var quotedEndRva = sectionRva + code.Count;
            Emit(0x48, 0x83, 0xC6, 0x02);
            var quotedDoneJump = EmitNearJump(0xE9);
            var unquotedRva = sectionRva + code.Count;
            var unquotedLoopRva = sectionRva + code.Count;
            Emit(0x66, 0x83, 0x3E, 0x00);
            var unquotedDoneZero = EmitNearJump2(0x0F, 0x84);
            Emit(0x66, 0x83, 0x3E, 0x20);
            var unquotedDoneSpace = EmitNearJump2(0x0F, 0x84);
            Emit(0x48, 0x83, 0xC6, 0x02);
            var unquotedBack = EmitNearJump(0xE9);
            var doneRva = sectionRva + code.Count;
            PatchRel32(doneAtZero, doneRva);
            PatchRel32(unquoted, unquotedRva);
            PatchRel32(quotedDoneZero, doneRva);
            PatchRel32(quotedEnd, quotedEndRva);
            PatchRel32(quotedBack, quotedLoopRva);
            PatchRel32(quotedDoneJump, doneRva);
            PatchRel32(unquotedDoneZero, doneRva);
            PatchRel32(unquotedDoneSpace, doneRva);
            PatchRel32(unquotedBack, unquotedLoopRva);
        }
        void InitCommandLine()
        {
            CallIat(6);
            CheckRaxZero();
            Emit(0x48, 0x89, 0xC6);
            SkipCommandLineArg();
        }
        void StoreRuntimeArgCount(string target)
        {
            var slot = slots[target];
            InitCommandLine();
            Emit(0x45, 0x31, 0xC9);
            var loopRva = sectionRva + code.Count;
            SkipCommandLineSpaces();
            Emit(0x66, 0x83, 0x3E, 0x00);
            var doneCount = EmitNearJump2(0x0F, 0x84);
            Emit(0x41, 0xFF, 0xC1);
            SkipCommandLineArg();
            var back = EmitNearJump(0xE9);
            var doneCountRva = sectionRva + code.Count;
            PatchRel32(doneCount, doneCountRva);
            PatchRel32(back, loopRva);
            Emit(0x44, 0x89, 0xC8);

            Emit(0x89, 0xC3);
            Emit(0x83, 0xF8, 0x0A);
            var oneDigit = EmitNearJump2(0x0F, 0x8C);
            Emit(0x31, 0xD2);
            Emit(0xB9, 0x0A, 0x00, 0x00, 0x00);
            Emit(0xF7, 0xF1);
            Emit(0x04, 0x30);
            StoreByteFromAl(slot.BufferRva);
            Emit(0x80, 0xC2, 0x30);
            StoreByteFromDl(slot.BufferRva + 1);
            StoreDwordMem(slot.LenRva, 2);
            var done = EmitShortJump(0xEB);
            var oneDigitRva = sectionRva + code.Count;
            Emit(0x80, 0xC3, 0x30);
            StoreByteFromBl(slot.BufferRva);
            StoreDwordMem(slot.LenRva, 1);
            var doneRva = sectionRva + code.Count;
            PatchRel32(oneDigit, oneDigitRva);
            PatchShort(done, doneRva);
        }
        void StoreRuntimeArgValue(int index, string target)
        {
            var slot = slots[target];
            InitCommandLine();
            Emit(0x45, 0x31, 0xC9);
            var findLoopRva = sectionRva + code.Count;
            SkipCommandLineSpaces();
            Emit(0x66, 0x83, 0x3E, 0x00);
            var outOfRange = EmitNearJump2(0x0F, 0x84);
            Emit(0x41, 0x83, 0xF9, unchecked((byte)index));
            var found = EmitNearJump2(0x0F, 0x84);
            SkipCommandLineArg();
            Emit(0x41, 0xFF, 0xC1);
            var findBack = EmitNearJump(0xE9);
            var foundRva = sectionRva + code.Count;
            PatchRel32(found, foundRva);
            Emit(0x66, 0x83, 0x3E, 0x22);
            var unquotedCopy = EmitNearJump2(0x0F, 0x85);
            Emit(0x48, 0x83, 0xC6, 0x02);
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, slot.BufferRva, 7);
            Emit(0x45, 0x31, 0xC0);
            var quotedLoopRva = sectionRva + code.Count;
            Emit(0x41, 0x81, 0xF8);
            EmitUInt32(runtimeSlotBytes - 1);
            var quotedDoneByCap = EmitNearJump2(0x0F, 0x8D);
            Emit(0x66, 0x42, 0x8B, 0x04, 0x46);
            Emit(0x66, 0x85, 0xC0);
            var quotedDoneByNull = EmitNearJump2(0x0F, 0x84);
            Emit(0x66, 0x83, 0xF8, 0x22);
            var quotedDoneByQuote = EmitNearJump2(0x0F, 0x84);
            Emit(0x42, 0x88, 0x04, 0x07);
            Emit(0x41, 0xFF, 0xC0);
            var quotedBack = EmitNearJump(0xE9);
            var unquotedCopyRva = sectionRva + code.Count;
            PatchRel32(unquotedCopy, unquotedCopyRva);
            Lea(new byte[] { 0x48, 0x8D, 0x3D }, slot.BufferRva, 7);
            Emit(0x45, 0x31, 0xC0);
            var unquotedLoopRva = sectionRva + code.Count;
            Emit(0x41, 0x81, 0xF8);
            EmitUInt32(runtimeSlotBytes - 1);
            var unquotedDoneByCap = EmitNearJump2(0x0F, 0x8D);
            Emit(0x66, 0x42, 0x8B, 0x04, 0x46);
            Emit(0x66, 0x85, 0xC0);
            var unquotedDoneByNull = EmitNearJump2(0x0F, 0x84);
            Emit(0x66, 0x83, 0xF8, 0x20);
            var unquotedDoneBySpace = EmitNearJump2(0x0F, 0x84);
            Emit(0x42, 0x88, 0x04, 0x07);
            Emit(0x41, 0xFF, 0xC0);
            var unquotedBack = EmitNearJump(0xE9);
            var doneRva = sectionRva + code.Count;
            StoreR8dToMem(slot.LenRva);
            var afterDone = EmitShortJump(0xEB);
            var emptyRva = sectionRva + code.Count;
            StoreDwordMem(slot.LenRva, 0);
            var afterEmptyRva = sectionRva + code.Count;
            PatchRel32(findBack, findLoopRva);
            PatchRel32(outOfRange, emptyRva);
            failJumps.Add(quotedDoneByCap);
            PatchRel32(quotedDoneByNull, doneRva);
            PatchRel32(quotedDoneByQuote, doneRva);
            PatchRel32(quotedBack, quotedLoopRva);
            failJumps.Add(unquotedDoneByCap);
            PatchRel32(unquotedDoneByNull, doneRva);
            PatchRel32(unquotedDoneBySpace, doneRva);
            PatchRel32(unquotedBack, unquotedLoopRva);
            PatchShort(afterDone, afterEmptyRva);
        }
        void CloseRbx()
        {
            Emit(0x48, 0x89, 0xD9);
            CallIat(3);
        }

        Emit(0x48, 0x83, 0xEC, 0x58);
        foreach (var action in actions)
        {
            var op = action.GetValueOrDefault("op");
            if (op == "file_write")
            {
                OpenFile(action["path"], 0x40000000, 2);
                if (action.GetValueOrDefault("value_kind") == "slot")
                    WriteHandleFromSlot(action["value"]);
                else
                    WriteHandleFromStatic(action.GetValueOrDefault("value") ?? "");
                CloseRbx();
            }
            else if (op == "file_append")
            {
                OpenFile(action["path"], 0x40000000, 4);
                Emit(0x48, 0x89, 0xD9);
                Emit(0x31, 0xD2);
                Emit(0x45, 0x31, 0xC0);
                Emit(0x41, 0xB9, 0x02, 0x00, 0x00, 0x00);
                CallIat(4);
                if (action.GetValueOrDefault("value_kind") == "slot")
                    WriteHandleFromSlot(action["value"]);
                else
                    WriteHandleFromStatic(action.GetValueOrDefault("value") ?? "");
                CloseRbx();
            }
            else if (op == "file_load")
            {
                var slot = slots[action["target"]];
                OpenFile(action["path"], 0x80000000, 3);
                Emit(0x48, 0x89, 0xD9);
                Lea(new byte[] { 0x48, 0x8D, 0x15 }, slot.BufferRva, 7);
                Emit(0x41, 0xB8); EmitUInt32(runtimeSlotBytes);
                Lea(new byte[] { 0x4C, 0x8D, 0x0D }, slot.LenRva, 7);
                StoreStack32(0x20, 0);
                CallIat(2);
                CheckEaxZero();
                var nextRva = sectionRva + code.Count + 10;
                Emit(0x81, 0x3D);
                EmitUInt32(unchecked((uint)(slot.LenRva - nextRva)));
                EmitUInt32(runtimeSlotBytes);
                JeFail();
                CloseRbx();
            }
            else if (op == "print_runtime_slot")
            {
                var slot = slots[action["target"]];
                Emit(0xB9, 0xF5, 0xFF, 0xFF, 0xFF);
                CallIat(5);
                CheckRaxInvalidHandle();
                Emit(0x48, 0x89, 0xC3);
                WriteHandleFromSlot(action["target"]);
                WriteHandleFromStatic("\n");
            }
            else if (op == "print_stdout")
            {
                var textId = action["text"];
                var text = ir.Consts[textId].Value;
                if (text.Length > 0 && !text.EndsWith('\n')) text += "\n";
                Emit(0xB9, 0xF5, 0xFF, 0xFF, 0xFF);
                CallIat(5);
                CheckRaxInvalidHandle();
                Emit(0x48, 0x89, 0xC3);
                WriteHandleFromStatic(text);
            }
            else if (op == "command_arg_count")
            {
                StoreRuntimeArgCount(action["target"]);
            }
            else if (op == "command_arg_index")
            {
                StoreRuntimeArgValue(int.Parse(action["value"], CultureInfo.InvariantCulture), action["target"]);
            }
            else if (op == "exit")
            {
                // Emitted once at the end.
            }
            else
            {
                throw new CompileError("BACKEND", "B001", 0, 0, $"Unsupported file I/O backend action: {op}.");
            }
        }

        Emit(0x31, 0xC9);
        CallIat(7);
        var failRva = sectionRva + code.Count;
        Emit(0xB9, 0x01, 0x00, 0x00, 0x00);
        CallIat(7);
        foreach (var offsetPos in failJumps)
        {
            var nextRva = sectionRva + offsetPos + 4;
            var rel = failRva - nextRva;
            BitConverter.GetBytes(rel).CopyTo(code.ToArray(), offsetPos);
        }
        var codeBytes = code.ToArray();
        if (sectionRva + codeBytes.Length > importRva)
            throw new CompileError("BACKEND", "B001", 0, 0, $"File I/O backend code section overlaps import table: code end RVA 0x{sectionRva + codeBytes.Length:X}, import RVA 0x{importRva:X}.");
        foreach (var offsetPos in failJumps)
        {
            var nextRva = sectionRva + offsetPos + 4;
            var rel = failRva - nextRva;
            BitConverter.GetBytes(rel).CopyTo(codeBytes, offsetPos);
        }
        codeBytes.CopyTo(pe, sectionRaw);
        return pe;

        int GetPath(string path)
        {
            if (!pathRvas.TryGetValue(path, out var rva))
            {
                rva = AddUtf16(path);
                pathRvas[path] = rva;
            }
            return rva;
        }

        (int Rva, int Length) GetValue(string value)
        {
            if (!valueRvas.TryGetValue(value, out var info))
            {
                var rva = AddUtf8(value);
                info = (rva, Encoding.UTF8.GetByteCount(value));
                valueRvas[value] = info;
            }
            return info;
        }

        int AddUtf8(string value)
        {
            var bytes = Encoding.UTF8.GetBytes(value);
            var rva = dataCursor;
            dataCursor += Align(bytes.Length + 1, 8);
            if (dataCursor > slotLenStartRva)
                throw new CompileError("BACKEND", "B001", 0, 0, $"File I/O backend data section overlaps runtime slot metadata: data end RVA 0x{dataCursor:X}, slot metadata RVA 0x{slotLenStartRva:X}.");
            Array.Copy(bytes, 0, pe, RvaToRaw(rva), bytes.Length);
            return rva;
        }

        int AddUtf16(string value)
        {
            var bytes = Encoding.Unicode.GetBytes(value + "\0");
            var rva = dataCursor;
            dataCursor += Align(bytes.Length, 8);
            if (dataCursor > slotLenStartRva)
                throw new CompileError("BACKEND", "B001", 0, 0, $"File I/O backend data section overlaps runtime slot metadata: data end RVA 0x{dataCursor:X}, slot metadata RVA 0x{slotLenStartRva:X}.");
            Array.Copy(bytes, 0, pe, RvaToRaw(rva), bytes.Length);
            return rva;
        }

        static int Align(int value, int align) => (value + align - 1) & ~(align - 1);
        static int RvaToRaw(int rva) => sectionRaw + (rva - sectionRva);
    }

    static void WritePeHeader(byte[] pe, int sectionSize, int importRva, int importSize, ushort subsystem)
    {
        WriteAscii(pe, 0, "MZ");
        WriteUInt32(pe, 0x3c, 0x80);

        var peOffset = 0x80;
        WriteAscii(pe, peOffset, "PE\0\0");
        var coff = peOffset + 4;
        WriteUInt16(pe, coff, 0x8664);
        WriteUInt16(pe, coff + 2, 1);
        WriteUInt16(pe, coff + 16, 0xF0);
        WriteUInt16(pe, coff + 18, 0x22);

        var opt = coff + 20;
        WriteUInt16(pe, opt, 0x20b);
        pe[opt + 2] = 14;
        WriteUInt32(pe, opt + 4, (uint)sectionSize);
        WriteUInt32(pe, opt + 16, 0x1000);
        WriteUInt32(pe, opt + 20, 0x1000);
        WriteUInt64(pe, opt + 24, 0x140000000);
        WriteUInt32(pe, opt + 32, 0x1000);
        WriteUInt32(pe, opt + 36, 0x200);
        WriteUInt16(pe, opt + 40, 6);
        WriteUInt16(pe, opt + 48, 6);
        WriteUInt32(pe, opt + 56, (uint)(0x1000 + sectionSize));
        WriteUInt32(pe, opt + 60, 0x200);
        WriteUInt16(pe, opt + 68, subsystem);
        WriteUInt64(pe, opt + 72, 0x100000);
        WriteUInt64(pe, opt + 80, 0x1000);
        WriteUInt64(pe, opt + 88, 0x100000);
        WriteUInt64(pe, opt + 96, 0x1000);
        WriteUInt32(pe, opt + 108, 16);
        WriteUInt32(pe, opt + 120, (uint)importRva);
        WriteUInt32(pe, opt + 124, (uint)importSize);

        var section = opt + 0xF0;
        WriteAscii(pe, section, ".text\0\0\0");
        WriteUInt32(pe, section + 8, (uint)sectionSize);
        WriteUInt32(pe, section + 12, 0x1000);
        WriteUInt32(pe, section + 16, (uint)sectionSize);
        WriteUInt32(pe, section + 20, 0x200);
        WriteUInt32(pe, section + 36, 0xE0000020);
    }

    static List<Dictionary<string, string>> OrderedActionMaps(IrModel ir)
        => ir.Actions
            .OrderBy(pair => ActionIndex(pair.Key))
            .Select(pair => pair.Value)
            .ToList();

    static int ActionIndex(string id)
        => id.StartsWith("act_", StringComparison.Ordinal) && int.TryParse(id[4..], out var index) ? index : int.MaxValue;

    static bool HasFileIoActions(IrModel ir)
        => ir.Actions.Values.Any(action =>
            action.TryGetValue("op", out var op) &&
            op is "file_write" or "file_append" or "file_load" or "print_runtime_slot" or "command_arg_count" or "command_arg_index");

    static bool HasWindowActions(IrModel ir)
        => ir.Actions.Values.Any(action =>
            action.TryGetValue("op", out var op) &&
            (op.StartsWith("window_", StringComparison.Ordinal) || op.StartsWith("event_", StringComparison.Ordinal)));

    static byte[] BuildStdoutPe(string text)
    {
        const int sectionRaw = 0x200;
        const int sectionRva = 0x1000;
        const int sectionSize = 0x1000;
        const int messageRva = 0x1500;
        const int writtenRva = 0x1f00;
        const int importRva = 0x1300;
        const int iltRva = 0x1340;
        const int iatRva = 0x1360;
        const int dllNameRva = 0x1380;
        const int maxMessageBytes = 0x900;

        var messageBytes = Encoding.UTF8.GetBytes(text);
        if (messageBytes.Length > maxMessageBytes)
            throw new CompileError("BACKEND", "B004", 0, 0, $"stdout text too long for M15 stdout backend: {messageBytes.Length} bytes.");

        var pe = new byte[sectionRaw + sectionSize];
        WriteAscii(pe, 0, "MZ");
        WriteUInt32(pe, 0x3c, 0x80);

        var peOffset = 0x80;
        WriteAscii(pe, peOffset, "PE\0\0");
        var coff = peOffset + 4;
        WriteUInt16(pe, coff, 0x8664);
        WriteUInt16(pe, coff + 2, 1);
        WriteUInt16(pe, coff + 16, 0xF0);
        WriteUInt16(pe, coff + 18, 0x22);

        var opt = coff + 20;
        WriteUInt16(pe, opt, 0x20b);
        pe[opt + 2] = 14;
        WriteUInt32(pe, opt + 4, sectionSize);
        WriteUInt32(pe, opt + 16, sectionRva);
        WriteUInt32(pe, opt + 20, sectionRva);
        WriteUInt64(pe, opt + 24, 0x140000000);
        WriteUInt32(pe, opt + 32, 0x1000);
        WriteUInt32(pe, opt + 36, 0x200);
        WriteUInt16(pe, opt + 40, 6);
        WriteUInt16(pe, opt + 48, 6);
        WriteUInt32(pe, opt + 56, 0x2000);
        WriteUInt32(pe, opt + 60, 0x200);
        WriteUInt16(pe, opt + 68, 3);
        WriteUInt64(pe, opt + 72, 0x100000);
        WriteUInt64(pe, opt + 80, 0x1000);
        WriteUInt64(pe, opt + 88, 0x100000);
        WriteUInt64(pe, opt + 96, 0x1000);
        WriteUInt32(pe, opt + 108, 16);
        WriteUInt32(pe, opt + 120, importRva);
        WriteUInt32(pe, opt + 124, 0x100);

        var section = opt + 0xF0;
        WriteAscii(pe, section, ".text\0\0\0");
        WriteUInt32(pe, section + 8, sectionSize);
        WriteUInt32(pe, section + 12, sectionRva);
        WriteUInt32(pe, section + 16, sectionSize);
        WriteUInt32(pe, section + 20, sectionRaw);
        WriteUInt32(pe, section + 36, 0xE0000020);

        var code = new List<byte>();
        void Emit(params byte[] bytes) => code.AddRange(bytes);
        void EmitUInt32(uint value) => code.AddRange(BitConverter.GetBytes(value));
        void CallIat(int rva)
        {
            var nextRva = sectionRva + code.Count + 6;
            Emit(0xff, 0x15);
            EmitUInt32(unchecked((uint)(rva - nextRva)));
        }
        void Lea(byte[] prefix, int targetRva, int instructionLength)
        {
            var nextRva = sectionRva + code.Count + instructionLength;
            Emit(prefix);
            EmitUInt32(unchecked((uint)(targetRva - nextRva)));
        }

        Emit(0x48, 0x83, 0xec, 0x38);
        Emit(0xB9, 0xF5, 0xFF, 0xFF, 0xFF);
        CallIat(iatRva);
        Emit(0x48, 0x89, 0xC1);
        Lea(new byte[] { 0x48, 0x8D, 0x15 }, messageRva, 7);
        Emit(0x41, 0xB8);
        EmitUInt32((uint)messageBytes.Length);
        Lea(new byte[] { 0x4C, 0x8D, 0x0D }, writtenRva, 7);
        Emit(0x48, 0xC7, 0x44, 0x24, 0x20, 0, 0, 0, 0);
        CallIat(iatRva + 8);
        Emit(0x31, 0xC9);
        CallIat(iatRva + 16);
        code.CopyTo(pe, sectionRaw);

        var importRaw = RvaToRaw(importRva);
        WriteUInt32(pe, importRaw, iltRva);
        WriteUInt32(pe, importRaw + 12, dllNameRva);
        WriteUInt32(pe, importRaw + 16, iatRva);

        AddImport(pe, iltRva, iatRva, 0, 0x13a0, "GetStdHandle");
        AddImport(pe, iltRva, iatRva, 1, 0x13c0, "WriteFile");
        AddImport(pe, iltRva, iatRva, 2, 0x13d8, "ExitProcess");
        WriteAscii(pe, RvaToRaw(dllNameRva), "kernel32.dll\0");
        Array.Copy(messageBytes, 0, pe, RvaToRaw(messageRva), messageBytes.Length);
        return pe;

        static int RvaToRaw(int rva) => sectionRaw + (rva - sectionRva);
    }

    static void AddImport(byte[] pe, int iltRva, int iatRva, int index, int nameRva, string name)
    {
        WriteUInt64(pe, RvaToRawLocal(iltRva) + index * 8, (ulong)nameRva);
        WriteUInt64(pe, RvaToRawLocal(iatRva) + index * 8, (ulong)nameRva);
        var raw = RvaToRawLocal(nameRva);
        WriteUInt16(pe, raw, 0);
        WriteAscii(pe, raw + 2, name + "\0");

        static int RvaToRawLocal(int rva) => 0x200 + (rva - 0x1000);
    }

    static void WriteUInt16(byte[] bytes, int offset, ushort value)
        => BitConverter.GetBytes(value).CopyTo(bytes, offset);

    static void WriteUInt32(byte[] bytes, int offset, uint value)
        => BitConverter.GetBytes(value).CopyTo(bytes, offset);

    static void WriteUInt64(byte[] bytes, int offset, ulong value)
        => BitConverter.GetBytes(value).CopyTo(bytes, offset);

    static void WriteAscii(byte[] bytes, int offset, string value)
    {
        var encoded = Encoding.ASCII.GetBytes(value);
        Array.Copy(encoded, 0, bytes, offset, encoded.Length);
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

    static (string Backend, string Actions) BackendManifestInfo(string irPath)
    {
        var ir = ParseIr(irPath);
        if (HasFileIoActions(ir))
            return ("WindowsX64PE_FileIoBackend", string.Join(",", OrderedActionMaps(ir).Select(a => a["op"])));
        if (ir.Actions.TryGetValue("act_0", out var first) &&
            first.TryGetValue("op", out var op) &&
            op == "print_stdout")
            return ("WindowsX64PE_StdoutBackend", "print_stdout,exit");
        return ("WindowsX64PE_MessageBoxBackend", "show_message,exit");
    }

    static void WriteManifest(string manifestPath, string artifactPath, string sourcePath, string irPath, string backend, string target, string status, string actions)
    {
        var lines = new[]
        {
            $"ARTIFACT|{Esc(artifactPath.Replace('\\', '/'))}",
            $"SOURCE|{Esc(sourcePath.Replace('\\', '/'))}",
            $"IR|{Esc(irPath.Replace('\\', '/'))}",
            $"BACKEND|{backend}",
            $"TARGET|{target}",
            $"STATUS|{status}",
            $"ACTIONS|{actions}",
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
        List<Token> _tokens;
        readonly Dictionary<string, VarInfo> _vars = new(StringComparer.Ordinal);
        readonly List<(string Name, string Type, string Value)> _varList = new();
        readonly List<string> _flow = new();
        readonly List<string> _prints = new();
        readonly List<RuntimeAction> _runtimeActions = new();
        readonly HashSet<string> _runtimeSymbols = new(StringComparer.Ordinal);
        readonly Dictionary<string, List<Token>> _functions = new(StringComparer.Ordinal);
        readonly HashSet<string> _callStack = new(StringComparer.Ordinal);
        readonly HashSet<string> _definedWindows = new(StringComparer.Ordinal);
        readonly HashSet<string> _shownWindows = new(StringComparer.Ordinal);
        readonly HashSet<string> _definedEvents = new(StringComparer.Ordinal);
        readonly List<StatementRule> _statementRules;
        bool _inEvent = false;
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
        bool _parsingCondition = false;

        public Parser(List<Token> tokens)
        {
            _tokens = tokens;
            _statementRules =
            [
                new StatementRule(() => IsKeyword("define") && PeekKeyword("window"), ParseWindowStatement),
                new StatementRule(() => IsKeyword("set") && (PeekKeyword("title") || PeekKeyword("resolution") || PeekKeyword("resizable")) && PeekKeyword("of", 2), ParseWindowStatement),
                new StatementRule(() => (IsKeyword("show") || IsKeyword("run") || IsKeyword("close")) && PeekKeyword("window"), ParseWindowStatement),
                new StatementRule(() => IsKeyword("let"), ParseLegacyLetStatement),
                new StatementRule(() => IsKeyword("define"), ParseCanonicalDefineStatement),
                new StatementRule(() => IsKeyword("rename"), ParseRenameStatement),
                new StatementRule(() => IsKeyword("print"), ParsePrintStatement),
                new StatementRule(() => IsKeyword("title") || IsKeyword("set"), ParseTitleStatement),
                new StatementRule(() => IsKeyword("message") || IsKeyword("show"), ParseMessageStatement),
                new StatementRule(() => IsKeyword("write") || IsKeyword("load"), ParseFileIoStatement),
                new StatementRule(() => IsKeyword("add") || IsKeyword("remove") || IsKeyword("multiply") || IsKeyword("divide"), ParseAddOrMathUpdateStatement),
                new StatementRule(() => IsKeyword("exit"), ParseExitStatement),
                new StatementRule(() => IsKeyword("blend"), ParseBlendMixToCodeStatement),
                new StatementRule(() => IsKeyword("if"), ParseIfStatement),
                new StatementRule(() => IsKeyword("while"), ParseWhileStatement),
                new StatementRule(() => IsKeyword("call"), ParseFunctionCallStatement),
                new StatementRule(() => IsKeyword("when"), ParseWhenStatement),
            ];
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

            if (_message == null && _prints.Count > 0)
                ApplyMessage(PrintBufferMessage());
            if (_title == null && _prints.Count > 0)
            {
                _title = program;
                _titleExpr = $"str(\"{program}\")";
                _titleCommand = "print_default_title";
            }

            if (_runtimeActions.Count > 0)
            {
                _title ??= program;
                _titleExpr = _titleExpr == "" ? $"str(\"{program}\")" : _titleExpr;
                _titleCommand = _titleCommand == "" ? "runtime_default_title" : _titleCommand;
                _message ??= "";
                _messageExpr = _messageExpr == "" ? "runtime_actions" : _messageExpr;
                _messageCommand = _messageCommand == "" ? "runtime_actions" : _messageCommand;
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

            return new AstModel(program, _varList, _title!, _titleExpr, _titleCommand, _message!, _messageExpr, _messageCommand, _exitCode, _finalCommand, _flow, _runtimeActions);
        }

        void ParseStatement(bool apply, bool inIf)
        {
            SkipNewlines();

            if (CurrentIs("EOF"))
                throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected statement.");

            if (_inEvent && !(IsKeyword("close") && PeekKeyword("window")))
                throw new CompileError("SEMANTIC", "S081", Current.Line, Current.Column, $"Unsupported statement inside event block: '{Current.Value}'.");

            foreach (var rule in _statementRules)
                if (rule.Matches())
                {
                    rule.Parse(apply, inIf);
                    return;
                }

            if (IsKeyword("else"))
                throw new CompileError("PARSE", "P055", Current.Line, Current.Column, "Unexpected else without matching if.");

            if (IsKeyword("end") && PeekKeyword("if"))
                throw new CompileError("PARSE", "P056", Current.Line, Current.Column, "Unexpected end if without matching if.");

            if (IsKeyword("end") && PeekKeyword("while"))
                throw new CompileError("PARSE", "P081", Current.Line, Current.Column, "Unexpected end while without matching while.");

            if (IsKeyword("end") && PeekKeyword("function"))
                throw new CompileError("PARSE", "P091", Current.Line, Current.Column, "Unexpected end function without matching function.");

            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected statement.");
        }

        void ParseLegacyLetStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "let declarations inside compile-time if are not supported in M13.");
            ParseLet();
        }

        void ParseCanonicalDefineStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "define declarations inside compile-time if are not supported in M14A.");
            if (PeekKeyword("function") || (PeekKeyword("const") && PeekKeyword("function", 2)))
            {
                ParseFunctionDefinition();
                return;
            }
            ParseDefine();
        }

        void ParseRenameStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "rename inside compile-time if is not supported in M14A.");
            ParseRename();
        }

        void ParseWindowStatement(bool apply, bool inIf)
        {
            if (_prints.Count > 0)
                throw new CompileError("SEMANTIC", "S075", Current.Line, Current.Column, "Print is not supported with window actions.");

            if (IsKeyword("define") && PeekKeyword("window"))
            {
                ExpectKeyword("define");
                ExpectKeyword("window");
                ExpectKeyword("called");
                var nameTok = Expect("STRING", "window name");
                ExpectLine();
                if (_definedWindows.Count > 0 && !_definedWindows.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S073", nameTok.Line, nameTok.Column, "Only one window is supported in M15F.");
                if (_definedWindows.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S071", nameTok.Line, nameTok.Column, $"Window '{nameTok.Value}' is already defined.");
                _definedWindows.Add(nameTok.Value);
                if (apply)
                    _runtimeActions.Add(new RuntimeAction("window_create", "", "static", "", nameTok.Value));
            }
            else if (IsKeyword("set") && PeekKeyword("title"))
            {
                ExpectKeyword("set");
                ExpectKeyword("title");
                ExpectKeyword("of");
                var nameTok = Expect("STRING", "window name");
                ExpectKeyword("to");
                ExpectKeyword("string");
                var titleTok = Expect("STRING", "window title");
                ExpectLine();
                
                if (!_definedWindows.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S072", nameTok.Line, nameTok.Column, $"Window '{nameTok.Value}' is not defined.");

                if (apply)
                    _runtimeActions.Add(new RuntimeAction("window_set_title", "", "static", titleTok.Value, nameTok.Value));
            }
            else if (IsKeyword("set") && PeekKeyword("resolution"))
            {
                ExpectKeyword("set");
                ExpectKeyword("resolution");
                ExpectKeyword("of");
                var nameTok = Expect("STRING", "window name");
                ExpectKeyword("to");
                
                if (!_definedWindows.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S072", nameTok.Line, nameTok.Column, $"Window '{nameTok.Value}' is not defined.");
                
                var widthTok = Current;
                if (widthTok.Type == "INT")
                    Advance();
                else if (CurrentIs("MINUS"))
                {
                    Advance();
                    widthTok = Expect("INT", "resolution width");
                    widthTok = new Token("INT", "-" + widthTok.Value, widthTok.Line, widthTok.Column);
                }
                else
                    throw new CompileError("PARSE", "P107", Current.Line, Current.Column, "Expected integer for resolution width.");

                if (Current.Value.ToLower() != "x")
                    throw new CompileError("PARSE", "P108", Current.Line, Current.Column, "Expected 'x' between resolution dimensions.");
                Advance(); // consume 'x'

                var heightTok = Current;
                if (heightTok.Type == "INT")
                    Advance();
                else if (CurrentIs("MINUS"))
                {
                    Advance();
                    heightTok = Expect("INT", "resolution height");
                    heightTok = new Token("INT", "-" + heightTok.Value, heightTok.Line, heightTok.Column);
                }
                else
                    throw new CompileError("PARSE", "P109", Current.Line, Current.Column, "Expected integer for resolution height.");

                ExpectLine();

                if (!int.TryParse(widthTok.Value, out var w) || w <= 0 || !int.TryParse(heightTok.Value, out var h) || h <= 0)
                    throw new CompileError("SEMANTIC", "S070", widthTok.Line, widthTok.Column, "Window resolution dimensions must be positive integers.");

                if (apply)
                    _runtimeActions.Add(new RuntimeAction("window_set_resolution", "", "static", $"{w}x{h}", nameTok.Value));
            }
            else if (IsKeyword("set") && PeekKeyword("resizable"))
            {
                ExpectKeyword("set");
                ExpectKeyword("resizable");
                ExpectKeyword("of");
                var nameTok = Expect("STRING", "window name");
                ExpectKeyword("to");
                
                if (!_definedWindows.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S072", nameTok.Line, nameTok.Column, $"Window '{nameTok.Value}' is not defined.");
                
                var boolTok = Current;
                if (boolTok.Type != "BOOL")
                    throw new CompileError("PARSE", "P110", Current.Line, Current.Column, "Expected boolean for resizable value.");
                Advance();
                ExpectLine();

                if (apply)
                    _runtimeActions.Add(new RuntimeAction("window_set_resizable", "", "static", boolTok.Value, nameTok.Value));
            }
            else if (IsKeyword("close") && PeekKeyword("window"))
            {
                ExpectKeyword("close");
                ExpectKeyword("window");
                var nameTok = Expect("STRING", "window name");
                ExpectLine();

                if (!_definedWindows.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S080", nameTok.Line, nameTok.Column, $"Cannot close missing window '{nameTok.Value}'.");

                if (apply)
                    _runtimeActions.Add(new RuntimeAction("window_close", "", "static", "", nameTok.Value));
            }
            else if (IsKeyword("show"))
            {
                ExpectKeyword("show");
                ExpectKeyword("window");
                var nameTok = Expect("STRING", "window name");
                ExpectLine();
                
                if (!_definedWindows.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S072", nameTok.Line, nameTok.Column, $"Window '{nameTok.Value}' is not defined.");
                
                _shownWindows.Add(nameTok.Value);

                if (apply)
                    _runtimeActions.Add(new RuntimeAction("window_show", "", "static", "", nameTok.Value));
            }
            else if (IsKeyword("run"))
            {
                ExpectKeyword("run");
                ExpectKeyword("window");
                var nameTok = Expect("STRING", "window name");
                ExpectLine();
                
                if (!_definedWindows.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S072", nameTok.Line, nameTok.Column, $"Window '{nameTok.Value}' is not defined.");
                
                if (!_shownWindows.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S074", nameTok.Line, nameTok.Column, $"'run window' called before 'show window' for '{nameTok.Value}'.");
                
                if (apply)
                {
                    _runtimeActions.Add(new RuntimeAction("window_run", "", "static", "", nameTok.Value));
                    _finalCommand = "exit";
                }
            }
        }

        void ParseTitleStatement(bool apply, bool inIf)
        {
            if (IsKeyword("set") && PeekType("STRING"))
            {
                ParseSetValue(apply);
                return;
            }

            var title = IsKeyword("title") ? ParseTitleCommand() : ParseSetTitleTo();
            if (apply)
                ApplyTitle(title);
        }

        void ParsePrintStatement(bool apply, bool inIf)
        {
            if (_definedWindows.Count > 0)
                throw new CompileError("SEMANTIC", "S075", Current.Line, Current.Column, "Print is not supported with window actions.");

            if (IsRuntimePrint())
            {
                ExpectKeyword("print");
                var slotTok = Expect("STRING", "runtime string symbol");
                ExpectLine();
                if (apply)
                    _runtimeActions.Add(new RuntimeAction("print_runtime_slot", "", "slot", slotTok.Value, slotTok.Value));
                return;
            }

            var printed = ParsePrint();
            if (apply)
                AppendPrint(printed);
        }

        void ParseMessageStatement(bool apply, bool inIf)
        {
            var message = IsKeyword("message") ? ParseMessageCommand() : ParseShowMessage();
            if (apply)
                ApplyMessage(message);
        }

        void ParseExitStatement(bool apply, bool inIf)
        {
            ParseExit();
            if (apply)
                _finalCommand = "exit";
        }

        void ParseBlendMixToCodeStatement(bool apply, bool inIf)
        {
            ParseBlendMixToCode();
            if (apply)
                _finalCommand = "blend_mix_to_code";
        }

        void ParseIfStatement(bool apply, bool inIf)
        {
            if (inIf || _ifDepth > 0)
                throw new CompileError("PARSE", "P054", Current.Line, Current.Column, "Nested if statements are not supported in M13.");
            ParseCompileTimeIf(apply);
        }

        void ParseWhileStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("PARSE", "P082", Current.Line, Current.Column, "while inside compile-time if is not supported in M14C.");
            ParseWhile(apply);
        }

        void ParseFileIoStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("PARSE", "P100", Current.Line, Current.Column, "file I/O inside compile-time if is not supported in M15C.");
            if (IsKeyword("write"))
                ParseFileWrite(apply);
            else
                ParseFileLoad(apply);
        }

        void ParseAddOrMathUpdateStatement(bool apply, bool inIf)
        {
            if (IsKeyword("add") && LooksLikeFileAppend())
            {
                if (inIf)
                    throw new CompileError("PARSE", "P100", Current.Line, Current.Column, "file I/O inside compile-time if is not supported in M15C.");
                ParseFileAppend(apply);
                return;
            }
            ParseMathUpdate(apply);
        }

        void ParseMathUpdateStatement(bool apply, bool inIf)
        {
            ParseMathUpdate(apply);
        }

        void ParseFunctionCallStatement(bool apply, bool inIf)
        {
            ParseFunctionCall(apply);
        }

        void ApplyTitle(CommandExpr title)
        {
            _title = title.Value;
            _titleExpr = title.Repr;
            _titleCommand = title.Command;
        }

        void ApplyMessage(CommandExpr message)
        {
            _message = message.Value;
            _messageExpr = message.Repr;
            _messageCommand = message.Command;
        }

        void AppendPrint(ExprResult printed)
        {
            _prints.Add(FormatValue(printed));
            ApplyMessage(PrintBufferMessage());
        }

        CommandExpr PrintBufferMessage()
            => new(string.Join("\n", _prints), "print_buffer", "print");

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
            var expr = ParseTextLikeExpression("set title to", "P052", "Expected expression after set title to.");
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
            if (IsKeyword("message"))
            {
                ExpectKeyword("message");
                var legacyExpr = ParseExpression("show message", "P061", "Expected expression after show message.");
                ExpectLine();
                return new CommandExpr(legacyExpr.Value, legacyExpr.Repr, "show_message");
            }

            var canonicalString = IsKeyword("string");
            var expr = ParseTextLikeExpression("show", "P061", "Expected expression after show.");
            ExpectLine();
            return new CommandExpr(expr.Value, expr.Repr, canonicalString ? "show_string" : "show_value");
        }

        ExprResult ParsePrint()
        {
            ExpectKeyword("print");
            var expr = ParsePrintValueExpression();
            ExpectLine();
            return expr;
        }

        bool IsRuntimePrint()
            => IsKeyword("print") &&
               PeekType("STRING") &&
               (_pos + 1) < _tokens.Count &&
               _runtimeSymbols.Contains(_tokens[_pos + 1].Value);

        bool LooksLikeFileAppend()
        {
            for (var i = _pos + 1; i + 1 < _tokens.Count; i++)
            {
                if (_tokens[i].Type is "NEWLINE" or "EOF")
                    return false;
                if (_tokens[i].Type == "KEYWORD" && _tokens[i].Value == "to" &&
                    _tokens[i + 1].Type == "KEYWORD" && _tokens[i + 1].Value == "file")
                    return true;
            }
            return false;
        }

        void ParseFileWrite(bool apply)
        {
            ExpectKeyword("write");
            if (!IsKeyword("file"))
                throw new CompileError("PARSE", "P100", Current.Line, Current.Column, "Expected keyword \"file\" after write.");
            ExpectKeyword("file");
            var pathTok = ExpectFilePath();
            if (!IsKeyword("with"))
                throw new CompileError("PARSE", "P101", Current.Line, Current.Column, "Expected keyword \"with\" after file path.");
            ExpectKeyword("with");
            var value = ParseFileValue();
            ExpectLine();
            if (apply)
                _runtimeActions.Add(new RuntimeAction("file_write", pathTok.Value, value.Kind, value.Value, ""));
        }

        void ParseFileAppend(bool apply)
        {
            ExpectKeyword("add");
            var value = ParseFileValue();
            if (!IsKeyword("to"))
                throw new CompileError("PARSE", "P102", Current.Line, Current.Column, "Expected keyword \"to\" after add value.");
            ExpectKeyword("to");
            if (!IsKeyword("file"))
                throw new CompileError("PARSE", "P103", Current.Line, Current.Column, "Expected keyword \"file\" after add value to.");
            ExpectKeyword("file");
            var pathTok = ExpectFilePath();
            ExpectLine();
            if (apply)
                _runtimeActions.Add(new RuntimeAction("file_append", pathTok.Value, value.Kind, value.Value, ""));
        }

        void ParseFileLoad(bool apply)
        {
            ExpectKeyword("load");
            if (!IsKeyword("file"))
                throw new CompileError("PARSE", "P104", Current.Line, Current.Column, "Expected keyword \"file\" after load.");
            ExpectKeyword("file");
            var pathTok = ExpectFilePath();
            if (!IsKeyword("to"))
                throw new CompileError("PARSE", "P105", Current.Line, Current.Column, "Expected keyword \"to\" after load file path.");
            ExpectKeyword("to");
            var targetTok = Expect("STRING", "target symbol name");
            ExpectLine();

            if (!apply)
                return;

            var target = ResolveSymbol(targetTok, "S060", name => $"Cannot load file into missing symbol \"{name}\".");
            if (target.IsConst)
                throw new CompileError("SEMANTIC", "S063", targetTok.Line, targetTok.Column, $"Cannot load file into const symbol \"{targetTok.Value}\".");
            if (target.Type != "text")
                throw new CompileError("SEMANTIC", "S061", targetTok.Line, targetTok.Column, $"load file target \"{targetTok.Value}\" must be string or var text.");

            _vars[targetTok.Value] = target with { IsRuntime = true };
            _runtimeSymbols.Add(targetTok.Value);
            _runtimeActions.Add(new RuntimeAction("file_load", pathTok.Value, "slot", targetTok.Value, targetTok.Value));
        }

        Token ExpectFilePath()
        {
            var pathTok = Expect("STRING", "file path string");
            if (string.IsNullOrWhiteSpace(pathTok.Value))
                throw new CompileError("SEMANTIC", "S062", pathTok.Line, pathTok.Column, "File path cannot be empty.");
            return pathTok;
        }

        FileValue ParseFileValue()
        {
            if (IsExpressionEnd())
                throw new CompileError("PARSE", "P106", Current.Line, Current.Column, "Expected file value.");

            if (IsKeyword("string"))
            {
                var literal = ParseCanonicalStringLiteral();
                return new FileValue("static", RuntimeUnescape(literal.Value));
            }

            if (CurrentIs("STRING") && !PeekType("PLUS"))
            {
                var symbolTok = Advance();
                var info = ResolveSymbol(symbolTok, "S036", name => $"Unknown symbol \"{name}\".");
                if (info.IsRuntime)
                    return new FileValue("slot", symbolTok.Value);
                return new FileValue("static", FormatValue(new ExprResult(info.Type, info.Value, $"symbol({symbolTok.Value})")));
            }

            var value = ParseAddExpression(legacyQuotedStrings: false);
            return new FileValue("static", FormatValue(value));
        }

        static string RuntimeUnescape(string value)
            => value.Replace("\\r", "\r").Replace("\\n", "\n").Replace("\\t", "\t").Replace("\\\\", "\\");

        void ParseSetValue(bool apply)
        {
            ExpectKeyword("set");
            var targetTok = Expect("STRING", "symbol name");
            if (!IsKeyword("to"))
                throw new CompileError("PARSE", "P075", Current.Line, Current.Column, "Expected keyword \"to\" after set target.");
            ExpectKeyword("to");
            var value = ParseAddExpression();
            ExpectLine();
            if (apply)
                SetSymbolValue(targetTok, value);
        }

        void ParseMathUpdate(bool apply)
        {
            if (IsKeyword("add"))
            {
                ExpectKeyword("add");
                var value = ParseAddExpression();
                if (!IsKeyword("to"))
                    throw new CompileError("PARSE", "P076", Current.Line, Current.Column, "Expected keyword \"to\" after add expression.");
                ExpectKeyword("to");
                var target = Expect("STRING", "symbol name");
                ExpectLine();
                if (apply)
                    ApplyNumericUpdate(target, value, "+");
                return;
            }

            if (IsKeyword("remove"))
            {
                ExpectKeyword("remove");
                var value = ParseAddExpression();
                if (!IsKeyword("from"))
                    throw new CompileError("PARSE", "P077", Current.Line, Current.Column, "Expected keyword \"from\" after remove expression.");
                ExpectKeyword("from");
                var target = Expect("STRING", "symbol name");
                ExpectLine();
                if (apply)
                    ApplyNumericUpdate(target, value, "-");
                return;
            }

            if (IsKeyword("multiply"))
            {
                ExpectKeyword("multiply");
                var target = Expect("STRING", "symbol name");
                if (!IsKeyword("by"))
                    throw new CompileError("PARSE", "P078", Current.Line, Current.Column, "Expected keyword \"by\" after multiply target.");
                ExpectKeyword("by");
                var value = ParseAddExpression();
                ExpectLine();
                if (apply)
                    ApplyNumericUpdate(target, value, "*");
                return;
            }

            ExpectKeyword("divide");
            var divideTarget = Expect("STRING", "symbol name");
            if (!IsKeyword("by"))
                throw new CompileError("PARSE", "P079", Current.Line, Current.Column, "Expected keyword \"by\" after divide target.");
            ExpectKeyword("by");
            var divideValue = ParseAddExpression();
            ExpectLine();
            if (apply)
                ApplyNumericUpdate(divideTarget, divideValue, "/");
        }

        void ParseWhenStatement(bool apply, bool inIf)
        {
            ExpectKeyword("when");
            if (IsKeyword("closed"))
            {
                ExpectKeyword("closed");
                var nameTok = Expect("STRING", "window name");
                ExpectLine();

                if (!_definedWindows.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S076", nameTok.Line, nameTok.Column, $"Cannot attach closed event to missing window '{nameTok.Value}'.");
                
                var eventId = "closed_" + nameTok.Value;
                if (_definedEvents.Contains(eventId))
                    throw new CompileError("SEMANTIC", "S077", nameTok.Line, nameTok.Column, $"Duplicate closed event for window '{nameTok.Value}'.");
                _definedEvents.Add(eventId);

                if (apply) _runtimeActions.Add(new RuntimeAction("event_window_closed", "", "static", "", nameTok.Value));

                bool prevInEvent = _inEvent;
                _inEvent = true;

                SkipNewlines();
                while (!CurrentIs("EOF") && !(IsKeyword("end") && PeekKeyword("when")))
                {
                    ParseStatement(apply, inIf);
                    SkipNewlines();
                }

                _inEvent = prevInEvent;

                ExpectKeyword("end");
                ExpectKeyword("when");
                ExpectLine();

                if (apply) _runtimeActions.Add(new RuntimeAction("event_end", "", "static", "", nameTok.Value));
            }
            else if (IsKeyword("key") && PeekKeyword("pressed"))
            {
                ExpectKeyword("key");
                ExpectKeyword("pressed");
                var keyTok = Expect("STRING", "key name");
                ExpectLine();

                if (keyTok.Value != "Escape")
                    throw new CompileError("SEMANTIC", "S078", keyTok.Line, keyTok.Column, $"Unsupported key name '{keyTok.Value}'.");

                var eventId = "key_" + keyTok.Value;
                if (_definedEvents.Contains(eventId))
                    throw new CompileError("SEMANTIC", "S079", keyTok.Line, keyTok.Column, $"Duplicate key event for '{keyTok.Value}'.");
                _definedEvents.Add(eventId);

                if (apply) _runtimeActions.Add(new RuntimeAction("event_key_pressed", "", "static", keyTok.Value, ""));

                bool prevInEvent = _inEvent;
                _inEvent = true;

                SkipNewlines();
                while (!CurrentIs("EOF") && !(IsKeyword("end") && PeekKeyword("when")))
                {
                    ParseStatement(apply, inIf);
                    SkipNewlines();
                }

                _inEvent = prevInEvent;

                ExpectKeyword("end");
                ExpectKeyword("when");
                ExpectLine();

                if (apply) _runtimeActions.Add(new RuntimeAction("event_end", "", "static", keyTok.Value, ""));
            }
            else
            {
                throw new CompileError("PARSE", "P110", Current.Line, Current.Column, "Expected 'closed' or 'key pressed' after 'when'.");
            }
        }

        void ParseWhile(bool apply)
        {
            ExpectKeyword("while");
            var conditionTokens = ReadUntilLine();
            var body = ReadBlock("while", "P080", "Expected end while.");

            if (!apply)
                return;

            const int maxIterations = 10000;
            for (var iteration = 0; iteration < maxIterations; iteration++)
            {
                if (!EvaluateConditionTokens(conditionTokens))
                    return;
                RunTokenBlock(body);
            }

            throw new CompileError("SEMANTIC", "S047", Current.Line, Current.Column, "while iteration guard exceeded.");
        }

        void ParseFunctionDefinition()
        {
            ExpectKeyword("define");
            if (IsKeyword("const"))
                throw new CompileError("SEMANTIC", "S048", Current.Line, Current.Column, "const function is not supported.");
            ExpectKeyword("function");
            if (!IsKeyword("called"))
                throw new CompileError("PARSE", "P090", Current.Line, Current.Column, "Expected keyword \"called\" after define function.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "function name");
            if (_functions.ContainsKey(nameTok.Value))
                throw new CompileError("SEMANTIC", "S049", nameTok.Line, nameTok.Column, $"Function \"{nameTok.Value}\" is already defined.");
            ExpectLine();
            _functions[nameTok.Value] = ReadBlock("function", "P092", "Expected end function.");
        }

        void ParseFunctionCall(bool apply)
        {
            ExpectKeyword("call");
            if (!IsKeyword("function"))
                throw new CompileError("PARSE", "P093", Current.Line, Current.Column, "Expected keyword \"function\" after call.");
            ExpectKeyword("function");
            var nameTok = Expect("STRING", "function name");
            ExpectLine();

            if (!apply)
                return;

            if (!_functions.TryGetValue(nameTok.Value, out var body))
                throw new CompileError("SEMANTIC", "S050", nameTok.Line, nameTok.Column, $"Unknown function \"{nameTok.Value}\".");
            if (_callStack.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S051", nameTok.Line, nameTok.Column, $"Recursive function call \"{nameTok.Value}\" is not supported.");

            _callStack.Add(nameTok.Value);
            try
            {
                RunTokenBlock(body);
            }
            finally
            {
                _callStack.Remove(nameTok.Value);
            }
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
            CheckDuplicateSymbol(nameTok, "Variable");
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

            DefineSymbol(nameTok.Value, type, value);
            ExpectLine();
        }

        void ParseDefine()
        {
            ExpectKeyword("define");
            var isConst = false;
            if (IsKeyword("const"))
            {
                isConst = true;
                ExpectKeyword("const");
            }

            if (!CurrentIs("KEYWORD") || Current.Value is not ("string" or "int" or "float" or "double" or "bool" or "vec2" or "vec3" or "vec4" or "mat4" or "transform" or "quat" or "rect" or "circle" or "complex" or "color" or "angle" or "var"))
                throw new CompileError("PARSE", "P070", Current.Line, Current.Column, "Expected canonical type after \"define\".");
            var declaredType = Advance();

            if (!IsKeyword("called"))
                throw new CompileError("PARSE", "P071", Current.Line, Current.Column, "Expected keyword \"called\" after define type.");
            ExpectKeyword("called");

            if (!CurrentIs("STRING"))
                throw new CompileError("PARSE", "P072", Current.Line, Current.Column, "Expected quoted symbol name after \"called\".");
            var nameTok = Advance();
            CheckDuplicateSymbol(nameTok, "Symbol");

            if (!IsKeyword("be"))
                throw new CompileError("PARSE", "P073", Current.Line, Current.Column, "Expected keyword \"be\" after symbol name.");
            ExpectKeyword("be");

            if (IsKeyword("command"))
            {
                ParseCommandArgDefinition(declaredType.Value, nameTok, isConst);
                ExpectLine();
                return;
            }

            var value = ParseCanonicalValue(declaredType.Value);
            DefineSymbol(nameTok.Value, value.Type, value.Value, isConst);
            ExpectLine();
        }

        void ParseCommandArgDefinition(string declaredType, Token nameTok, bool isConst)
        {
            if (isConst)
                throw new CompileError("SEMANTIC", "S071", nameTok.Line, nameTok.Column, "const command arg targets are not supported.");

            ExpectKeyword("command");
            if (!IsKeyword("arg"))
                throw new CompileError("PARSE", "P110", Current.Line, Current.Column, "Expected keyword \"arg\" after \"command\".");
            ExpectKeyword("arg");

            if (IsKeyword("count"))
            {
                if (declaredType != "int" && declaredType != "var")
                    throw new CompileError("SEMANTIC", "S070", Current.Line, Current.Column, "command arg count must be defined as int.");
                ExpectKeyword("count");
                if (!IsExpressionEnd())
                    throw new CompileError("PARSE", "P114", Current.Line, Current.Column, "Unexpected tokens after command arg count.");
                DefineRuntimeSymbol(nameTok.Value, "int", "runtime(command_arg_count)", isConst: false);
                _runtimeActions.Add(new RuntimeAction("command_arg_count", "", "slot", nameTok.Value, nameTok.Value));
                return;
            }

            if (declaredType != "string" && declaredType != "var")
                throw new CompileError("SEMANTIC", "S070", Current.Line, Current.Column, "command arg index must be defined as string.");

            if (!CurrentIs("INT"))
            {
                if (CurrentIs("MINUS"))
                    throw new CompileError("SEMANTIC", "S072", Current.Line, Current.Column, "command arg index cannot be negative.");
                throw new CompileError("PARSE", "P111", Current.Line, Current.Column, "Expected integer command arg index.");
            }

            var indexTok = Advance();
            if (!int.TryParse(indexTok.Value, NumberStyles.None, CultureInfo.InvariantCulture, out var index))
                throw new CompileError("PARSE", "P111", indexTok.Line, indexTok.Column, "Expected integer command arg index.");
            if (index < 0)
                throw new CompileError("SEMANTIC", "S072", indexTok.Line, indexTok.Column, "command arg index cannot be negative.");
            if (!IsExpressionEnd())
                throw new CompileError("PARSE", "P113", Current.Line, Current.Column, "Unexpected tokens after command arg index.");

            DefineRuntimeSymbol(nameTok.Value, "text", $"runtime(command_arg_{index})", isConst: false);
            _runtimeActions.Add(new RuntimeAction("command_arg_index", "", "index", index.ToString(CultureInfo.InvariantCulture), nameTok.Value));
        }

        ExprResult ParseCanonicalValue(string declaredType)
        {
            if (declaredType == "string")
            {
                if (!IsKeyword("string"))
                    throw new CompileError("SEMANTIC", "S030", Current.Line, Current.Column, "define string requires string literal syntax: string \"...\".");
                return ParseCanonicalStringLiteral();
            }

            if (declaredType == "int")
            {
                if (!CurrentIs("INT"))
                    throw new CompileError("SEMANTIC", "S031", Current.Line, Current.Column, "define int requires an integer literal.");
                return ParseIntLiteral();
            }

            if (declaredType == "float")
            {
                if (!CurrentIs("DECIMAL") && !CurrentIs("INT"))
                    throw new CompileError("SEMANTIC", "S037", Current.Line, Current.Column, "define float requires a numeric literal.");
                var n = ParseNumericLiteral("float");
                return new ExprResult("float", n.Value, n.Repr);
            }

            if (declaredType == "double")
            {
                if (!CurrentIs("DECIMAL") && !CurrentIs("INT"))
                    throw new CompileError("SEMANTIC", "S038", Current.Line, Current.Column, "define double requires a numeric literal.");
                var n = ParseNumericLiteral("double");
                return new ExprResult("double", n.Value, n.Repr);
            }

            if (declaredType == "bool")
            {
                if (!CurrentIs("BOOL"))
                    throw new CompileError("SEMANTIC", "S032", Current.Line, Current.Column, "define bool requires true or false.");
                return ParseBoolLiteral();
            }

            if (IsVector(declaredType))
            {
                if (!CurrentIs("LBRACKET"))
                    throw new CompileError("SEMANTIC", "S100", Current.Line, Current.Column, $"define {declaredType} requires vector literal syntax.");
                var vector = ParseVectorLiteral(legacyQuotedStrings: false);
                if (vector.Type != declaredType)
                    throw new CompileError("SEMANTIC", "S101", Current.Line, Current.Column, $"Cannot assign {vector.Type} literal to {declaredType} symbol.");
                return vector;
            }

            if (IsMatrixType(declaredType))
            {
                if (!CurrentWordIs("identity"))
                    throw new CompileError("SEMANTIC", "S130", Current.Line, Current.Column, $"define {declaredType} requires identity for now.");
                var idTok = Advance();
                return new ExprResult(declaredType, FormatMatrix(IdentityMatrix()), $"identity({idTok.Value})");
            }

            if (declaredType == "quat")
                return ParseQuaternionLiteral();

            if (declaredType == "rect")
                return ParseRectLiteral();

            if (declaredType == "circle")
                return ParseCircleLiteral();

            if (declaredType == "complex")
                return ParseComplexValueExpression();

            if (declaredType == "color")
                return ParseColorLiteralExpression();

            if (declaredType == "angle")
            {
                var angle = ParseNumberMaybeAngleLiteral();
                if (angle.Type != "angle")
                    throw new CompileError("SEMANTIC", "S111", Current.Line, Current.Column, "define angle requires numeric literal followed by deg or rad.");
                return angle;
            }

            if (IsKeyword("color"))
                return ParseColorLiteralExpression();

            if (IsKeyword("string"))
                return ParseCanonicalStringLiteral();

            if (CurrentIs("INT") || CurrentIs("DECIMAL"))
                return ParseNumberMaybeAngleLiteral();

            if (CurrentIs("BOOL"))
                return ParseBoolLiteral();

            if (CurrentIs("LBRACKET"))
                return ParseVectorLiteral(legacyQuotedStrings: false);

            if (CurrentWordIs("identity"))
            {
                var idTok = Advance();
                return new ExprResult("mat4", FormatMatrix(IdentityMatrix()), $"identity({idTok.Value})");
            }

            if (CurrentWordIs("quat"))
                return ParseQuaternionLiteral();

            if (CurrentWordIs("rect"))
                return ParseRectLiteral();

            if (CurrentWordIs("circle"))
                return ParseCircleLiteral();

            if (CurrentWordIs("complex"))
                return ParseComplexLiteral();

            throw new CompileError("SEMANTIC", "S033", Current.Line, Current.Column, "define var requires string, int, bool, vector, matrix, transform, quaternion, geometry, complex, color, or angle literal value.");
        }

        ExprResult ParseQuaternionLiteral()
        {
            if (CurrentWordIs("identity"))
            {
                var idTok = Advance();
                return new ExprResult("quat", FormatQuaternion(0, 0, 0, 1), $"quat_identity({idTok.Value})");
            }

            ExpectWord("quat", "P150", "Expected quat literal.");
            ExpectWord("from", "P151", "Expected from in quaternion axis-angle literal.");
            ExpectWord("axis", "P152", "Expected axis in quaternion axis-angle literal.");
            var axis = ParseAddExpression(legacyQuotedStrings: false);
            if (axis.Type != "vec3")
                throw new CompileError("SEMANTIC", "S150", Current.Line, Current.Column, "Quaternion axis must be vec3.");
            ExpectWord("angle", "P153", "Expected angle in quaternion axis-angle literal.");
            var angle = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(angle.Type) && !IsAngle(angle.Type))
                throw new CompileError("SEMANTIC", "S151", Current.Line, Current.Column, "Quaternion angle must be numeric or angle.");
            var q = QuaternionFromAxisAngle(ToVector(axis), ToNumber(angle));
            return new ExprResult("quat", FormatQuaternion(q), $"quat_axis_angle({axis.Repr},{angle.Repr})");
        }

        ExprResult ParseRectLiteral()
        {
            ExpectWord("rect", "P160", "Expected rect literal.");
            var origin = ParseAddExpression(legacyQuotedStrings: false);
            if (origin.Type != "vec2")
                throw new CompileError("SEMANTIC", "S160", Current.Line, Current.Column, "rect origin must be vec2.");
            ExpectWord("size", "P161", "Expected size in rect literal.");
            var size = ParseAddExpression(legacyQuotedStrings: false);
            if (size.Type != "vec2")
                throw new CompileError("SEMANTIC", "S160", Current.Line, Current.Column, "rect size must be vec2.");
            var s = ToVector(size);
            if (s[0] < 0 || s[1] < 0)
                throw new CompileError("SEMANTIC", "S161", Current.Line, Current.Column, "rect size cannot be negative.");
            return new ExprResult("rect", FormatRect(ToVector(origin), s), $"rect({origin.Repr},{size.Repr})");
        }

        ExprResult ParseCircleLiteral()
        {
            ExpectWord("circle", "P162", "Expected circle literal.");
            ExpectWord("center", "P163", "Expected center in circle literal.");
            var center = ParseAddExpression(legacyQuotedStrings: false);
            if (center.Type != "vec2")
                throw new CompileError("SEMANTIC", "S162", Current.Line, Current.Column, "circle center must be vec2.");
            ExpectWord("radius", "P164", "Expected radius in circle literal.");
            var radius = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(radius.Type))
                throw new CompileError("SEMANTIC", "S162", Current.Line, Current.Column, "circle radius must be numeric.");
            var r = ToNumber(radius);
            if (r < 0)
                throw new CompileError("SEMANTIC", "S163", Current.Line, Current.Column, "circle radius cannot be negative.");
            return new ExprResult("circle", FormatCircle(ToVector(center), r), $"circle({center.Repr},{radius.Repr})");
        }

        ExprResult ParseComplexValueExpression()
        {
            var value = ParseAddExpression(legacyQuotedStrings: false);
            if (value.Type == "complex")
                return value;
            if (IsNumeric(value.Type))
                return new ExprResult("complex", FormatComplex(ToNumber(value), 0), $"complex({value.Repr},0)");
            throw new CompileError("SEMANTIC", "S170", Current.Line, Current.Column, "define complex requires a complex expression.");
        }

        ExprResult ParseComplexLiteral()
        {
            ExpectWord("complex", "P170", "Expected complex literal.");
            var real = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(real.Type))
                throw new CompileError("SEMANTIC", "S170", Current.Line, Current.Column, "Complex real part must be numeric.");
            Expect("COMMA", "comma between complex parts");
            var imag = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(imag.Type))
                throw new CompileError("SEMANTIC", "S170", Current.Line, Current.Column, "Complex imaginary part must be numeric.");
            return new ExprResult("complex", FormatComplex(ToNumber(real), ToNumber(imag)), $"complex({real.Repr},{imag.Repr})");
        }

        ExprResult ParseCanonicalStringLiteral()
        {
            ExpectKeyword("string");
            var s = Expect("STRING", "string literal");
            return new ExprResult("text", s.Value, $"str(\"{s.Value}\")");
        }

        ExprResult ParseIntLiteral()
        {
            var i = Expect("INT", "integer literal");
            return new ExprResult("int", i.Value, $"int({i.Value})");
        }

        ExprResult ParseBoolLiteral()
        {
            var b = Expect("BOOL", "bool literal");
            return new ExprResult("bool", b.Value, $"bool({b.Value})");
        }

        ExprResult ParseNumericLiteral(string type)
        {
            var token = CurrentIs("DECIMAL") ? Expect("DECIMAL", "decimal literal") : Expect("INT", "integer literal");
            return new ExprResult(type, FormatNumber(double.Parse(token.Value, CultureInfo.InvariantCulture), type), $"{type}({token.Value})");
        }

        ExprResult ParseNumberMaybeAngleLiteral()
        {
            var token = CurrentIs("DECIMAL") ? Expect("DECIMAL", "decimal literal") : Expect("INT", "integer literal");
            var number = double.Parse(token.Value, CultureInfo.InvariantCulture);
            var numericType = token.Type == "INT" ? "int" : "double";

            if (IsAngleUnitToken(Current))
            {
                var unit = Advance();
                var radians = unit.Value == "deg" ? number * Math.PI / 180.0 : number;
                return new ExprResult("angle", FormatNumber(radians, "double"), $"angle({token.Value}{unit.Value})");
            }

            if (CurrentWordIs("i"))
            {
                Advance();
                return new ExprResult("complex", FormatComplex(0, number), $"imag({token.Value})");
            }

            return new ExprResult(numericType, FormatNumber(number, numericType), $"{numericType}({token.Value})");
        }

        static bool IsAngleUnitToken(Token token)
            => (token.Type == "KEYWORD" || token.Type == "IDENT") && token.Value is "deg" or "rad";

        ExprResult ParseColorLiteralExpression()
        {
            if (IsKeyword("color"))
                ExpectKeyword("color");

            if (!CurrentIs("STRING") && !CurrentIs("IDENT") && !CurrentIs("KEYWORD"))
                throw new CompileError("PARSE", "P140", Current.Line, Current.Column, "Expected color literal.");

            var token = Advance();
            var normalized = NormalizeColorLiteral(token);
            return new ExprResult("color", normalized, $"color({normalized})");
        }

        static string NormalizeColorLiteral(Token token)
        {
            var raw = token.Value.Trim();
            var named = raw.ToLowerInvariant() switch
            {
                "black" => "#000000",
                "white" => "#FFFFFF",
                "red" => "#FF0000",
                "green" => "#00FF00",
                "blue" => "#0000FF",
                "transparent" => "#00000000",
                _ => raw,
            };

            if (!named.StartsWith("#", StringComparison.Ordinal))
                throw new CompileError("SEMANTIC", "S110", token.Line, token.Column, $"Unknown color literal \"{raw}\".");

            var hex = named[1..];
            if (hex.Length != 6 && hex.Length != 8)
                throw new CompileError("SEMANTIC", "S110", token.Line, token.Column, "Color hex literal must be #RRGGBB or #RRGGBBAA.");

            if (hex.Any(ch => !Uri.IsHexDigit(ch)))
                throw new CompileError("SEMANTIC", "S110", token.Line, token.Column, "Color hex literal contains non-hex characters.");

            return "#" + hex.ToUpperInvariant();
        }

        static int ColorToWin32ColorRef(string normalizedColor)
        {
            var hex = normalizedColor.TrimStart('#');
            var r = Convert.ToInt32(hex[..2], 16);
            var g = Convert.ToInt32(hex[2..4], 16);
            var b = Convert.ToInt32(hex[4..6], 16);
            return (b << 16) | (g << 8) | r;
        }

        ExprResult FormatSymbolReference(Token token)
        {
            if (!SymbolExists(token.Value) && token.Value.Contains('.', StringComparison.Ordinal))
                return FormatComponentReference(token);
            var info = ResolveSymbol(token, "S036", name => $"Unknown symbol \"{name}\".");
            return new ExprResult(info.Type, info.Value, $"symbol({token.Value})");
        }

        static bool IsNumeric(string type) => type is "int" or "float" or "double";
        static bool IsVector(string type) => type is "vec2" or "vec3" or "vec4";
        static bool IsMatrixType(string type) => type is "mat4" or "transform";
        static bool IsQuaternion(string type) => type == "quat";
        static bool IsGeometryType(string type) => type is "rect" or "circle";
        static bool IsComplex(string type) => type == "complex";
        static bool IsColor(string type) => type == "color";
        static bool IsAngle(string type) => type == "angle";

        static double ToNumber(ExprResult expr)
            => double.Parse(expr.Value, CultureInfo.InvariantCulture);

        static double[] ToVector(ExprResult expr)
        {
            if (!IsVector(expr.Type))
                throw new CompileError("SEMANTIC", "S102", 0, 0, "Expected vector value.");
            var inner = expr.Value.Trim();
            if (inner.StartsWith("[") && inner.EndsWith("]"))
                inner = inner[1..^1];
            if (string.IsNullOrWhiteSpace(inner))
                return Array.Empty<double>();
            return inner.Split(',').Select(part => double.Parse(part.Trim(), CultureInfo.InvariantCulture)).ToArray();
        }

        static string FormatVector(double[] values)
            => "[" + string.Join(",", values.Select(value => FormatNumber(value, "double"))) + "]";

        static bool TrySplitComponentName(string name, out string symbolName, out string component)
        {
            symbolName = "";
            component = "";
            var dot = name.IndexOf('.', StringComparison.Ordinal);
            if (dot < 0)
                return false;
            if (dot == 0 || dot == name.Length - 1 || name.IndexOf('.', dot + 1) >= 0)
                return false;
            symbolName = name[..dot];
            component = name[(dot + 1)..];
            return true;
        }

        static int VectorComponentIndex(string type, string component)
        {
            var index = component switch
            {
                "x" => 0,
                "y" => 1,
                "z" => 2,
                "w" => 3,
                _ => -1,
            };

            return type switch
            {
                "vec2" when index is >= 0 and <= 1 => index,
                "vec3" when index is >= 0 and <= 2 => index,
                "vec4" when index is >= 0 and <= 3 => index,
                _ => -1,
            };
        }

        ExprResult FormatComponentReference(Token token)
        {
            if (!TrySplitComponentName(token.Value, out var symbolName, out var component))
                throw new CompileError("SEMANTIC", "S108", token.Line, token.Column, $"Invalid component reference \"{token.Value}\".");

            if (!_vars.TryGetValue(symbolName, out var info))
                throw new CompileError("SEMANTIC", "S108", token.Line, token.Column, $"Unknown component base symbol \"{symbolName}\".");

            if (!IsVector(info.Type))
                throw new CompileError("SEMANTIC", "S108", token.Line, token.Column, $"Component access requires vector symbol \"{symbolName}\".");

            var index = VectorComponentIndex(info.Type, component);
            if (index < 0)
                throw new CompileError("SEMANTIC", "S108", token.Line, token.Column, $"Vector {info.Type} does not have component \"{component}\".");

            var values = ToVector(new ExprResult(info.Type, info.Value, $"symbol({symbolName})"));
            return new ExprResult("double", FormatNumber(values[index], "double"), $"component({token.Value})");
        }

        static string VectorTypeForCount(int count) => count switch
        {
            2 => "vec2",
            3 => "vec3",
            4 => "vec4",
            _ => "",
        };

        static double[] IdentityMatrix()
            => new double[]
            {
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            };

        static double[] ToMatrix(ExprResult expr)
        {
            if (!IsMatrixType(expr.Type))
                throw new CompileError("SEMANTIC", "S130", 0, 0, "Expected mat4 or transform value.");
            var inner = expr.Value.Trim();
            if (inner.StartsWith("[") && inner.EndsWith("]"))
                inner = inner[1..^1];
            var values = inner.Split(',').Select(part => double.Parse(part.Trim(), CultureInfo.InvariantCulture)).ToArray();
            if (values.Length != 16)
                throw new CompileError("SEMANTIC", "S130", 0, 0, "mat4 value must have 16 components.");
            return values;
        }

        static string FormatMatrix(double[] values)
            => "[" + string.Join(",", values.Select(value => FormatNumber(value, "double"))) + "]";

        static double[] ToQuaternion(ExprResult expr)
        {
            if (!IsQuaternion(expr.Type))
                throw new CompileError("SEMANTIC", "S150", 0, 0, "Expected quaternion value.");
            var values = ParseBracketedDoubles(expr.Value, "quaternion", 4);
            var len = Math.Sqrt(values.Sum(v => v * v));
            if (Math.Abs(len) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S152", 0, 0, "Quaternion cannot have zero length.");
            return values.Select(v => v / len).ToArray();
        }

        static string FormatQuaternion(params double[] values)
            => "[" + string.Join(",", values.Select(value => FormatNumber(value, "double"))) + "]";

        static double[] QuaternionFromAxisAngle(double[] axis, double radians)
        {
            if (axis.Length != 3)
                throw new CompileError("SEMANTIC", "S150", 0, 0, "Quaternion axis must be vec3.");
            var len = Math.Sqrt(axis.Sum(v => v * v));
            if (Math.Abs(len) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S152", 0, 0, "Quaternion axis must be non-zero.");
            var half = radians / 2.0;
            var scale = Math.Sin(half) / len;
            return new[] { axis[0] * scale, axis[1] * scale, axis[2] * scale, Math.Cos(half) };
        }

        static double[] QuaternionMultiply(double[] a, double[] b)
        {
            var ax = a[0]; var ay = a[1]; var az = a[2]; var aw = a[3];
            var bx = b[0]; var by = b[1]; var bz = b[2]; var bw = b[3];
            return new[]
            {
                aw * bx + ax * bw + ay * bz - az * by,
                aw * by - ax * bz + ay * bw + az * bx,
                aw * bz + ax * by - ay * bx + az * bw,
                aw * bw - ax * bx - ay * by - az * bz,
            };
        }

        static double[] RotateVectorByQuaternion(double[] vector, double[] quat)
        {
            if (vector.Length != 3)
                throw new CompileError("SEMANTIC", "S154", 0, 0, "rotate vector requires vec3.");
            var q = quat;
            var v = new[] { vector[0], vector[1], vector[2], 0.0 };
            var qi = new[] { -q[0], -q[1], -q[2], q[3] };
            var r = QuaternionMultiply(QuaternionMultiply(q, v), qi);
            return new[] { r[0], r[1], r[2] };
        }

        static double[] SlerpQuaternion(double[] a, double[] b, double t)
        {
            var q1 = a.ToArray();
            var q2 = b.ToArray();
            var dot = q1.Select((v, i) => v * q2[i]).Sum();
            if (dot < 0.0)
            {
                q2 = q2.Select(v => -v).ToArray();
                dot = -dot;
            }

            if (dot > 0.9995)
            {
                var linear = q1.Select((v, i) => v + t * (q2[i] - v)).ToArray();
                var len = Math.Sqrt(linear.Sum(v => v * v));
                return linear.Select(v => v / len).ToArray();
            }

            dot = Math.Clamp(dot, -1.0, 1.0);
            var theta0 = Math.Acos(dot);
            var theta = theta0 * t;
            var sinTheta = Math.Sin(theta);
            var sinTheta0 = Math.Sin(theta0);
            var s0 = Math.Cos(theta) - dot * sinTheta / sinTheta0;
            var s1 = sinTheta / sinTheta0;
            return q1.Select((v, i) => s0 * v + s1 * q2[i]).ToArray();
        }

        static double[] EulerFromQuaternion(double[] q)
        {
            var x = q[0]; var y = q[1]; var z = q[2]; var w = q[3];

            var sinrCosp = 2.0 * (w * x + y * z);
            var cosrCosp = 1.0 - 2.0 * (x * x + y * y);
            var roll = Math.Atan2(sinrCosp, cosrCosp);

            var sinp = 2.0 * (w * y - z * x);
            var pitch = Math.Abs(sinp) >= 1.0 ? Math.CopySign(Math.PI / 2.0, sinp) : Math.Asin(sinp);

            var sinyCosp = 2.0 * (w * z + x * y);
            var cosyCosp = 1.0 - 2.0 * (y * y + z * z);
            var yaw = Math.Atan2(sinyCosp, cosyCosp);

            return new[] { roll, pitch, yaw };
        }

        static double[] ParseBracketedDoubles(string value, string label, int expectedCount)
        {
            var inner = value.Trim();
            if (inner.StartsWith("[") && inner.EndsWith("]"))
                inner = inner[1..^1];
            var parts = inner.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (parts.Length != expectedCount)
                throw new CompileError("SEMANTIC", "S150", 0, 0, $"Expected {expectedCount} values in {label}.");
            return parts.Select(part => double.Parse(part, CultureInfo.InvariantCulture)).ToArray();
        }

        static string FormatRect(double[] origin, double[] size)
            => $"rect({FormatVector(origin)},{FormatVector(size)})";

        static string FormatCircle(double[] center, double radius)
            => $"circle({FormatVector(center)},{FormatNumber(radius, "double")})";

        static (double X, double Y, double W, double H) ToRect(ExprResult expr)
        {
            if (expr.Type != "rect")
                throw new CompileError("SEMANTIC", "S160", 0, 0, "Expected rect value.");
            var value = expr.Value.Trim();
            if (!value.StartsWith("rect(", StringComparison.Ordinal) || !value.EndsWith(")", StringComparison.Ordinal))
                throw new CompileError("SEMANTIC", "S160", 0, 0, "Invalid rect value.");
            var inner = value[5..^1];
            var split = inner.IndexOf("],[", StringComparison.Ordinal);
            if (split < 0)
                throw new CompileError("SEMANTIC", "S160", 0, 0, "Invalid rect value.");
            var origin = ToVector(new ExprResult("vec2", inner[..(split + 1)], "rect_origin"));
            var size = ToVector(new ExprResult("vec2", inner[(split + 2)..], "rect_size"));
            return (origin[0], origin[1], size[0], size[1]);
        }

        static (double X, double Y, double R) ToCircle(ExprResult expr)
        {
            if (expr.Type != "circle")
                throw new CompileError("SEMANTIC", "S162", 0, 0, "Expected circle value.");
            var value = expr.Value.Trim();
            if (!value.StartsWith("circle(", StringComparison.Ordinal) || !value.EndsWith(")", StringComparison.Ordinal))
                throw new CompileError("SEMANTIC", "S162", 0, 0, "Invalid circle value.");
            var inner = value[7..^1];
            var split = inner.LastIndexOf(",", StringComparison.Ordinal);
            if (split < 0)
                throw new CompileError("SEMANTIC", "S162", 0, 0, "Invalid circle value.");
            var center = ToVector(new ExprResult("vec2", inner[..split], "circle_center"));
            var radius = double.Parse(inner[(split + 1)..], CultureInfo.InvariantCulture);
            return (center[0], center[1], radius);
        }

        static (double R, double I) ToComplex(ExprResult expr)
        {
            if (IsNumeric(expr.Type))
                return (ToNumber(expr), 0);
            if (!IsComplex(expr.Type))
                throw new CompileError("SEMANTIC", "S170", 0, 0, "Expected complex value.");
            var raw = expr.Value.Trim();
            if (!raw.EndsWith("i", StringComparison.Ordinal))
                throw new CompileError("SEMANTIC", "S170", 0, 0, "Invalid complex value.");
            var body = raw[..^1];
            var split = -1;
            for (var i = 1; i < body.Length; i++)
                if (body[i] is '+' or '-')
                    split = i;
            if (split < 0)
                throw new CompileError("SEMANTIC", "S170", 0, 0, "Invalid complex value.");
            var real = double.Parse(body[..split], CultureInfo.InvariantCulture);
            var imag = double.Parse(body[split..], CultureInfo.InvariantCulture);
            return (real, imag);
        }

        static string FormatComplex(double real, double imag)
        {
            var r = FormatNumber(real, "double");
            var absI = FormatNumber(Math.Abs(imag), "double");
            var sign = imag < 0 ? "-" : "+";
            return $"{r}{sign}{absI}i";
        }

        static double[] MultiplyMatrix(double[] a, double[] b)
        {
            var result = new double[16];
            for (var row = 0; row < 4; row++)
                for (var col = 0; col < 4; col++)
                    result[row * 4 + col] =
                        a[row * 4 + 0] * b[0 * 4 + col] +
                        a[row * 4 + 1] * b[1 * 4 + col] +
                        a[row * 4 + 2] * b[2 * 4 + col] +
                        a[row * 4 + 3] * b[3 * 4 + col];
            return result;
        }

        static double[] TranslationMatrix(double[] v)
        {
            if (v.Length != 3)
                throw new CompileError("SEMANTIC", "S131", 0, 0, "translate requires vec3 value.");
            var m = IdentityMatrix();
            m[3] = v[0];
            m[7] = v[1];
            m[11] = v[2];
            return m;
        }

        static double[] ScaleMatrix(double[] v)
        {
            if (v.Length != 3)
                throw new CompileError("SEMANTIC", "S131", 0, 0, "scale requires vec3 value.");
            var m = IdentityMatrix();
            m[0] = v[0];
            m[5] = v[1];
            m[10] = v[2];
            return m;
        }

        static double[] RotationMatrix(string axis, double radians)
        {
            var c = Math.Cos(radians);
            var s = Math.Sin(radians);
            var m = IdentityMatrix();
            switch (axis)
            {
                case "x":
                    m[5] = c; m[6] = -s; m[9] = s; m[10] = c;
                    break;
                case "y":
                    m[0] = c; m[2] = s; m[8] = -s; m[10] = c;
                    break;
                case "z":
                    m[0] = c; m[1] = -s; m[4] = s; m[5] = c;
                    break;
                default:
                    throw new CompileError("SEMANTIC", "S132", 0, 0, "rotate axis must be x, y, or z.");
            }
            return m;
        }

        static double[] TransformVector(double[] m, double[] v, bool point)
        {
            if (v.Length != 3)
                throw new CompileError("SEMANTIC", "S133", 0, 0, "transform point/direction requires vec3 value.");
            var w = point ? 1.0 : 0.0;
            return new[]
            {
                m[0] * v[0] + m[1] * v[1] + m[2] * v[2] + m[3] * w,
                m[4] * v[0] + m[5] * v[1] + m[6] * v[2] + m[7] * w,
                m[8] * v[0] + m[9] * v[1] + m[10] * v[2] + m[11] * w,
            };
        }

        static string PromoteNumericType(string left, string right, string op)
        {
            if (op == "/" && left == "int" && right == "int")
                return "double";
            if (left == "double" || right == "double")
                return "double";
            if (left == "float" || right == "float")
                return "float";
            return "int";
        }

        static string FormatNumber(double value, string type)
        {
           if (Math.Abs(value) < 0.0000000001)
             value = 0;

          if (type == "int")
             return ((long)Math.Round(value)).ToString(CultureInfo.InvariantCulture);

             return value.ToString("0.##########", CultureInfo.InvariantCulture);
        }

        static string FormatValue(ExprResult expr) => expr.Type == "bool" ? expr.Value.ToLowerInvariant() : expr.Value;

        ExprResult ApplyLogical(string op, ExprResult left, ExprResult right)
        {
            if (left.Type != "bool" || right.Type != "bool")
                throw new CompileError("SEMANTIC", "S041", Current.Line, Current.Column, $"{op} requires bool operands.");
            var value = op == "and"
                ? left.Value == "true" && right.Value == "true"
                : left.Value == "true" || right.Value == "true";
            return new ExprResult("bool", value.ToString().ToLowerInvariant(), $"{op}({left.Repr},{right.Repr})");
        }

        ExprResult ApplyPlus(ExprResult left, ExprResult right)
        {
            if (left.Type == "text" && right.Type == "text")
                return new ExprResult("text", left.Value + right.Value, $"plus({left.Repr},{right.Repr})");
            if (IsComplex(left.Type) || IsComplex(right.Type))
                return ApplyComplexBinary("+", left, right);
            if (IsVector(left.Type) || IsVector(right.Type))
                return ApplyVectorBinary("+", left, right);
            if (IsNumeric(left.Type) && IsNumeric(right.Type))
                return ApplyNumericBinary("+", left, right);
            throw new CompileError("SEMANTIC", "S011", Current.Line, Current.Column, "Type mismatch in expression.");
        }

        ExprResult ApplyComplexBinary(string op, ExprResult left, ExprResult right)
        {
            if ((!IsComplex(left.Type) && !IsNumeric(left.Type)) || (!IsComplex(right.Type) && !IsNumeric(right.Type)))
                throw new CompileError("SEMANTIC", "S171", Current.Line, Current.Column, "Complex operation requires complex or numeric operands.");
            var l = ToComplex(left);
            var r = ToComplex(right);
            var result = op switch
            {
                "+" => (R: l.R + r.R, I: l.I + r.I),
                "-" => (R: l.R - r.R, I: l.I - r.I),
                "*" => (R: l.R * r.R - l.I * r.I, I: l.R * r.I + l.I * r.R),
                "/" => ComplexDivide(l, r),
                _ => throw new CompileError("SEMANTIC", "S171", Current.Line, Current.Column, $"Unsupported complex operator {op}."),
            };
            return new ExprResult("complex", FormatComplex(result.R, result.I), $"complex_{op}({left.Repr},{right.Repr})");
        }

        static (double R, double I) ComplexDivide((double R, double I) left, (double R, double I) right)
        {
            var denom = right.R * right.R + right.I * right.I;
            if (Math.Abs(denom) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S172", 0, 0, "Complex division by zero.");
            return ((left.R * right.R + left.I * right.I) / denom, (left.I * right.R - left.R * right.I) / denom);
        }

        ExprResult ApplyVectorBinary(string op, ExprResult left, ExprResult right)
        {
            if (op is "+" or "-")
            {
                if (!IsVector(left.Type) || !IsVector(right.Type) || left.Type != right.Type)
                    throw new CompileError("SEMANTIC", "S102", Current.Line, Current.Column, $"Vector {op} requires matching vector operands.");
                var l = ToVector(left);
                var r = ToVector(right);
                var result = l.Select((value, index) => op == "+" ? value + r[index] : value - r[index]).ToArray();
                return new ExprResult(left.Type, FormatVector(result), $"{op}({left.Repr},{right.Repr})");
            }

            if (op == "*")
            {
                if (IsVector(left.Type) && IsNumeric(right.Type))
                {
                    var scalar = ToNumber(right);
                    var result = ToVector(left).Select(value => value * scalar).ToArray();
                    return new ExprResult(left.Type, FormatVector(result), $"mul({left.Repr},{right.Repr})");
                }
                if (IsNumeric(left.Type) && IsVector(right.Type))
                {
                    var scalar = ToNumber(left);
                    var result = ToVector(right).Select(value => scalar * value).ToArray();
                    return new ExprResult(right.Type, FormatVector(result), $"mul({left.Repr},{right.Repr})");
                }
            }

            if (op == "/")
            {
                if (!IsVector(left.Type) || !IsNumeric(right.Type))
                    throw new CompileError("SEMANTIC", "S102", Current.Line, Current.Column, "Vector division requires vector / numeric scalar.");
                var scalar = ToNumber(right);
                if (Math.Abs(scalar) < 0.0000000001)
                    throw new CompileError("SEMANTIC", "S046", Current.Line, Current.Column, "Division by zero.");
                var result = ToVector(left).Select(value => value / scalar).ToArray();
                return new ExprResult(left.Type, FormatVector(result), $"div({left.Repr},{right.Repr})");
            }

            throw new CompileError("SEMANTIC", "S102", Current.Line, Current.Column, $"Unsupported vector operator {op}.");
        }

        ExprResult ApplyNumericBinary(string op, ExprResult left, ExprResult right)
        {
            if (IsComplex(left.Type) || IsComplex(right.Type))
                return ApplyComplexBinary(op, left, right);

            if (IsVector(left.Type) || IsVector(right.Type))
                return ApplyVectorBinary(op, left, right);

            if (!IsNumeric(left.Type) || !IsNumeric(right.Type))
                throw new CompileError("SEMANTIC", "S044", Current.Line, Current.Column, "Numeric expression requires numeric operands.");

            if (op == "%" && (left.Type != "int" || right.Type != "int"))
                throw new CompileError("SEMANTIC", "S045", Current.Line, Current.Column, "Modulo only supports integer operands.");

            var l = ToNumber(left);
            var r = ToNumber(right);
            if ((op == "/" || op == "%") && Math.Abs(r) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S046", Current.Line, Current.Column, "Division by zero.");

            var type = op == "%" ? "int" : PromoteNumericType(left.Type, right.Type, op);
            var value = op switch
            {
                "+" => l + r,
                "-" => l - r,
                "*" => l * r,
                "/" => l / r,
                "%" => l % r,
                "^" => Math.Pow(l, r),
                _ => throw new CompileError("SEMANTIC", "S044", Current.Line, Current.Column, "Unknown numeric operator."),
            };

            if (op is "+" or "-" or "*" or "^" && type == "int")
                value = Math.Round(value);
            return new ExprResult(type, FormatNumber(value, type), $"{op}({left.Repr},{right.Repr})");
        }

        ExprResult ApplyScalarUnaryFunction(Token functionTok, ExprResult value)
        {
            var acceptsAngle = functionTok.Value is "sin" or "cos" or "tan";
            if (!IsNumeric(value.Type) && !(acceptsAngle && IsAngle(value.Type)))
                throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires a numeric operand." + (acceptsAngle ? " Angle operands are also accepted." : ""));

            var n = ToNumber(value);
            var result = functionTok.Value switch
            {
                "abs" => Math.Abs(n),
                "sqrt" => n < 0 ? throw new CompileError("SEMANTIC", "S091", functionTok.Line, functionTok.Column, "sqrt requires a non-negative operand.") : Math.Sqrt(n),
                "floor" => Math.Floor(n),
                "ceil" => Math.Ceiling(n),
                "round" => Math.Round(n, MidpointRounding.AwayFromZero),
                "sin" => Math.Sin(n),
                "cos" => Math.Cos(n),
                "tan" => Math.Tan(n),
                "log" => n <= 0 ? throw new CompileError("SEMANTIC", "S092", functionTok.Line, functionTok.Column, "log requires an operand greater than 0.") : Math.Log(n),
                "log10" => n <= 0 ? throw new CompileError("SEMANTIC", "S092", functionTok.Line, functionTok.Column, "log10 requires an operand greater than 0.") : Math.Log10(n),
                "exp" => Math.Exp(n),
                _ => throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"Unknown scalar math function \"{functionTok.Value}\"."),
            };

            return new ExprResult("double", FormatNumber(result, "double"), $"{functionTok.Value}({value.Repr})");
        }

        ExprResult ApplyScalarBinaryFunction(Token functionTok, ExprResult left, ExprResult right)
        {
            if (!IsNumeric(left.Type) || !IsNumeric(right.Type))
                throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires numeric operands.");

            var l = ToNumber(left);
            var r = ToNumber(right);
            var result = functionTok.Value switch
            {
                "min" => Math.Min(l, r),
                "max" => Math.Max(l, r),
                "pow" => Math.Pow(l, r),
                _ => throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"Unknown scalar math function \"{functionTok.Value}\"."),
            };

            var type = PromoteNumericType(left.Type, right.Type, functionTok.Value);
            if (functionTok.Value == "pow")
                type = "double";
            if (type == "int" && Math.Abs(result - Math.Round(result)) > 0.0000000001)
                type = "double";
            return new ExprResult(type, FormatNumber(result, type), $"{functionTok.Value}({left.Repr},{right.Repr})");
        }

        ExprResult ApplyClampFunction(Token functionTok, ExprResult value, ExprResult min, ExprResult max)
        {
            if (!IsNumeric(value.Type) || !IsNumeric(min.Type) || !IsNumeric(max.Type))
                throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, "clamp requires numeric operands.");

            var lo = ToNumber(min);
            var hi = ToNumber(max);
            if (lo > hi)
                throw new CompileError("SEMANTIC", "S093", functionTok.Line, functionTok.Column, "clamp minimum cannot be greater than maximum.");

            var n = ToNumber(value);
            var result = Math.Min(Math.Max(n, lo), hi);
            var type = PromoteNumericType(PromoteNumericType(value.Type, min.Type, "clamp"), max.Type, "clamp");
            if (type == "int" && Math.Abs(result - Math.Round(result)) > 0.0000000001)
                type = "double";
            return new ExprResult(type, FormatNumber(result, type), $"clamp({value.Repr},{min.Repr},{max.Repr})");
        }

        ExprResult ApplyAdvancedScalarUnary(Token functionTok, ExprResult value)
        {
            if (!IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires a numeric operand.");
            var n = ToNumber(value);
            var result = functionTok.Value switch
            {
                "saturate" => Math.Min(Math.Max(n, 0), 1),
                "sign" => Math.Sign(n),
                "fract" => n - Math.Floor(n),
                _ => throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, $"Unknown advanced scalar function \"{functionTok.Value}\"."),
            };
            return new ExprResult("double", FormatNumber(result, "double"), $"{functionTok.Value}({value.Repr})");
        }

        ExprResult ApplyStepFunction(Token functionTok, ExprResult edge, ExprResult value)
        {
            if (!IsNumeric(edge.Type) || !IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, "step requires numeric operands.");
            return new ExprResult("double", ToNumber(value) < ToNumber(edge) ? "0" : "1", $"step({edge.Repr},{value.Repr})");
        }

        ExprResult ApplySmoothStepFunction(Token functionTok, ExprResult edge0, ExprResult edge1, ExprResult value)
        {
            if (!IsNumeric(edge0.Type) || !IsNumeric(edge1.Type) || !IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, "smoothstep requires numeric operands.");
            var lo = ToNumber(edge0);
            var hi = ToNumber(edge1);
            if (Math.Abs(hi - lo) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S121", functionTok.Line, functionTok.Column, "smoothstep edges cannot be equal.");
            var t = Math.Min(Math.Max((ToNumber(value) - lo) / (hi - lo), 0), 1);
            var result = t * t * (3 - 2 * t);
            return new ExprResult("double", FormatNumber(result, "double"), $"smoothstep({edge0.Repr},{edge1.Repr},{value.Repr})");
        }

        ExprResult ApplyInverseLerpFunction(Token functionTok, ExprResult a, ExprResult b, ExprResult value)
        {
            if (!IsNumeric(a.Type) || !IsNumeric(b.Type) || !IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, "inverse lerp requires numeric operands.");
            var start = ToNumber(a);
            var end = ToNumber(b);
            if (Math.Abs(end - start) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S121", functionTok.Line, functionTok.Column, "inverse lerp range cannot be zero.");
            var result = (ToNumber(value) - start) / (end - start);
            return new ExprResult("double", FormatNumber(result, "double"), $"inverse_lerp({a.Repr},{b.Repr},{value.Repr})");
        }

        ExprResult ApplyRemapFunction(Token functionTok, ExprResult value, ExprResult inMin, ExprResult inMax, ExprResult outMin, ExprResult outMax)
        {
            if (!IsNumeric(value.Type) || !IsNumeric(inMin.Type) || !IsNumeric(inMax.Type) || !IsNumeric(outMin.Type) || !IsNumeric(outMax.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, "remap requires numeric operands.");
            var a = ToNumber(inMin);
            var b = ToNumber(inMax);
            if (Math.Abs(b - a) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S121", functionTok.Line, functionTok.Column, "remap input range cannot be zero.");
            var t = (ToNumber(value) - a) / (b - a);
            var result = ToNumber(outMin) + (ToNumber(outMax) - ToNumber(outMin)) * t;
            return new ExprResult("double", FormatNumber(result, "double"), $"remap({value.Repr},{inMin.Repr},{inMax.Repr},{outMin.Repr},{outMax.Repr})");
        }

        ExprResult ApplyLerpFunction(Token functionTok, ExprResult a, ExprResult b, ExprResult t)
        {
            if (!IsNumeric(t.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, "lerp factor must be numeric.");
            var factor = ToNumber(t);
            if (IsNumeric(a.Type) && IsNumeric(b.Type))
            {
                var result = ToNumber(a) + (ToNumber(b) - ToNumber(a)) * factor;
                return new ExprResult("double", FormatNumber(result, "double"), $"lerp({a.Repr},{b.Repr},{t.Repr})");
            }
            if (IsVector(a.Type) && IsVector(b.Type) && a.Type == b.Type)
            {
                var av = ToVector(a);
                var bv = ToVector(b);
                var result = av.Select((component, index) => component + (bv[index] - component) * factor).ToArray();
                return new ExprResult(a.Type, FormatVector(result), $"lerp({a.Repr},{b.Repr},{t.Repr})");
            }
            throw new CompileError("SEMANTIC", "S122", functionTok.Line, functionTok.Column, "lerp requires matching numeric or vector endpoints.");
        }

        ExprResult ApplyDistanceFunction(Token functionTok, ExprResult a, ExprResult b)
        {
            if (!IsVector(a.Type) || !IsVector(b.Type) || a.Type != b.Type)
                throw new CompileError("SEMANTIC", "S122", functionTok.Line, functionTok.Column, "distance requires matching vector operands.");
            var av = ToVector(a);
            var bv = ToVector(b);
            var result = Math.Sqrt(av.Select((component, index) => component - bv[index]).Sum(delta => delta * delta));
            return new ExprResult("double", FormatNumber(result, "double"), $"distance({a.Repr},{b.Repr})");
        }

        ExprResult ApplyReflectFunction(Token functionTok, ExprResult dir, ExprResult normal)
        {
            if (!IsVector(dir.Type) || !IsVector(normal.Type) || dir.Type != normal.Type)
                throw new CompileError("SEMANTIC", "S122", functionTok.Line, functionTok.Column, "reflect requires matching vector operands.");
            var d = ToVector(dir);
            var n = ToVector(normal);
            var dot = d.Select((component, index) => component * n[index]).Sum();
            var result = d.Select((component, index) => component - 2 * dot * n[index]).ToArray();
            return new ExprResult(dir.Type, FormatVector(result), $"reflect({dir.Repr},{normal.Repr})");
        }

        ExprResult ApplyProjectFunction(Token functionTok, ExprResult value, ExprResult onto)
        {
            if (!IsVector(value.Type) || !IsVector(onto.Type) || value.Type != onto.Type)
                throw new CompileError("SEMANTIC", "S122", functionTok.Line, functionTok.Column, "project requires matching vector operands.");
            var v = ToVector(value);
            var o = ToVector(onto);
            var denom = o.Sum(component => component * component);
            if (Math.Abs(denom) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S123", functionTok.Line, functionTok.Column, "project target vector cannot be zero.");
            var scale = v.Select((component, index) => component * o[index]).Sum() / denom;
            var result = o.Select(component => component * scale).ToArray();
            return new ExprResult(value.Type, FormatVector(result), $"project({value.Repr},{onto.Repr})");
        }

        ExprResult ApplyClampLengthFunction(Token functionTok, ExprResult value, ExprResult max)
        {
            if (!IsVector(value.Type) || !IsNumeric(max.Type))
                throw new CompileError("SEMANTIC", "S122", functionTok.Line, functionTok.Column, "clamp length requires vector and numeric max length.");
            var limit = ToNumber(max);
            if (limit < 0)
                throw new CompileError("SEMANTIC", "S124", functionTok.Line, functionTok.Column, "clamp length max cannot be negative.");
            var vector = ToVector(value);
            var len = Math.Sqrt(vector.Sum(component => component * component));
            if (len <= limit || Math.Abs(len) < 0.0000000001)
                return value;
            var result = vector.Select(component => component / len * limit).ToArray();
            return new ExprResult(value.Type, FormatVector(result), $"clamp_length({value.Repr},{max.Repr})");
        }

        ExprResult ApplyMatrixFunction(Token functionTok)
        {
            var name = functionTok.Value;
            if (name == "translate")
            {
                var v = ParseUnaryExpression(false);
                if (v.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S131", functionTok.Line, functionTok.Column, "translate requires vec3 operand.");
                return new ExprResult("mat4", FormatMatrix(TranslationMatrix(ToVector(v))), $"translate({v.Repr})");
            }
            if (name == "scale")
            {
                var v = ParseUnaryExpression(false);
                if (v.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S131", functionTok.Line, functionTok.Column, "scale requires vec3 operand.");
                return new ExprResult("mat4", FormatMatrix(ScaleMatrix(ToVector(v))), $"scale({v.Repr})");
            }
            if (name == "rotate")
            {
                if (!CurrentWordIs("x") && !CurrentWordIs("y") && !CurrentWordIs("z"))
                    throw new CompileError("SEMANTIC", "S132", functionTok.Line, functionTok.Column, "rotate axis must be x, y, or z.");
                var axis = Advance().Value;
                var angle = ParseUnaryExpression(false);
                if (!IsNumeric(angle.Type) && !IsAngle(angle.Type))
                    throw new CompileError("SEMANTIC", "S132", functionTok.Line, functionTok.Column, "rotate angle must be numeric or angle.");
                return new ExprResult("mat4", FormatMatrix(RotationMatrix(axis, ToNumber(angle))), $"rotate({axis},{angle.Repr})");
            }
            if (name == "matmul")
            {
                var left = ParseAddExpression(false);
                Expect("COMMA", "comma between matmul arguments");
                var right = ParseAddExpression(false);
                if (!IsMatrixType(left.Type) || !IsMatrixType(right.Type))
                    throw new CompileError("SEMANTIC", "S130", functionTok.Line, functionTok.Column, "matmul requires matrix or transform operands.");
                return new ExprResult("mat4", FormatMatrix(MultiplyMatrix(ToMatrix(left), ToMatrix(right))), $"matmul({left.Repr},{right.Repr})");
            }
            throw new CompileError("SEMANTIC", "S130", functionTok.Line, functionTok.Column, $"Unknown matrix function \"{name}\".");
        }

        ExprResult ApplyTransformFunction(Token functionTok)
        {
            if (CurrentWordIs("point") || CurrentWordIs("direction"))
            {
                var isPoint = Current.Value == "point";
                Advance();
                var matrix = ParseAddExpression(false);
                Expect("COMMA", "comma between transform arguments");
                var value = ParseAddExpression(false);
                if (!IsMatrixType(matrix.Type))
                    throw new CompileError("SEMANTIC", "S133", functionTok.Line, functionTok.Column, "transform point/direction requires mat4 or transform operand.");
                if (value.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S133", functionTok.Line, functionTok.Column, "transform point/direction value must be vec3.");
                var result = TransformVector(ToMatrix(matrix), ToVector(value), isPoint);
                return new ExprResult("vec3", FormatVector(result), $"transform_{(isPoint ? "point" : "direction")}({matrix.Repr},{value.Repr})");
            }
            throw new CompileError("SEMANTIC", "S133", functionTok.Line, functionTok.Column, "Expected point or direction after transform.");
        }

        ExprResult ApplyComposeTransform(Token functionTok)
        {
            ExpectWord("transform", "P150", "Expected transform after compose.");
            ExpectWord("position", "P151", "Expected position in compose transform.");
            var position = ParseAddExpression(false);
            ExpectWord("rotation", "P152", "Expected rotation in compose transform.");
            if (!CurrentWordIs("x") && !CurrentWordIs("y") && !CurrentWordIs("z"))
                throw new CompileError("SEMANTIC", "S132", functionTok.Line, functionTok.Column, "compose transform rotation axis must be x, y, or z.");
            var axis = Advance().Value;
            var angle = ParseUnaryExpression(false);
            ExpectWord("scale", "P153", "Expected scale in compose transform.");
            var scale = ParseAddExpression(false);
            if (position.Type != "vec3" || scale.Type != "vec3")
                throw new CompileError("SEMANTIC", "S134", functionTok.Line, functionTok.Column, "compose transform requires vec3 position and vec3 scale.");
            if (!IsNumeric(angle.Type) && !IsAngle(angle.Type))
                throw new CompileError("SEMANTIC", "S132", functionTok.Line, functionTok.Column, "compose transform rotation angle must be numeric or angle.");
            var matrix = MultiplyMatrix(MultiplyMatrix(TranslationMatrix(ToVector(position)), RotationMatrix(axis, ToNumber(angle))), ScaleMatrix(ToVector(scale)));
            return new ExprResult("transform", FormatMatrix(matrix), $"compose_transform({position.Repr},{axis},{angle.Repr},{scale.Repr})");
        }

        static bool IsScalarUnaryFunctionName(string value)
            => value is "abs" or "sqrt" or "floor" or "ceil" or "round" or "sin" or "cos" or "tan" or "log" or "log10" or "exp";

        static bool IsScalarBinaryFunctionName(string value)
            => value is "min" or "max" or "pow";

        static bool IsMathConstantName(string value)
            => value is "pi" or "e";

        static bool IsVectorUnaryFunctionName(string value)
            => value is "length" or "normalize";

        static bool IsVectorBinaryFunctionName(string value)
            => value is "dot" or "cross";

        static bool IsAdvancedMathFunctionName(string value)
            => value is "saturate" or "sign" or "fract" or "step" or "smoothstep" or "inverse" or "remap" or "lerp" or "distance" or "reflect" or "project" or "clamp" or "translate" or "scale" or "rotate" or "matmul" or "compose" or "slerp" or "euler";

        static bool IsComplexFunctionName(string value)
            => value is "real" or "imag" or "magnitude" or "phase";

        static bool IsGeometryFunctionName(string value)
            => value is "point" or "rect" or "closest";

        ExprResult ApplyVectorUnaryFunction(Token functionTok, ExprResult value)
        {
            if (!IsVector(value.Type))
                throw new CompileError("SEMANTIC", "S102", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires a vector operand.");

            var vector = ToVector(value);
            var len = Math.Sqrt(vector.Sum(component => component * component));

            if (functionTok.Value == "length")
                return new ExprResult("double", FormatNumber(len, "double"), $"length({value.Repr})");

            if (functionTok.Value == "normalize")
            {
                if (Math.Abs(len) < 0.0000000001)
                    throw new CompileError("SEMANTIC", "S103", functionTok.Line, functionTok.Column, "normalize requires a non-zero vector.");
                var result = vector.Select(component => component / len).ToArray();
                return new ExprResult(value.Type, FormatVector(result), $"normalize({value.Repr})");
            }

            throw new CompileError("SEMANTIC", "S102", functionTok.Line, functionTok.Column, $"Unknown vector math function \"{functionTok.Value}\".");
        }

        ExprResult ApplyVectorBinaryFunction(Token functionTok, ExprResult left, ExprResult right)
        {
            if (!IsVector(left.Type) || !IsVector(right.Type))
                throw new CompileError("SEMANTIC", "S102", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires vector operands.");
            if (left.Type != right.Type && functionTok.Value == "dot")
                throw new CompileError("SEMANTIC", "S104", functionTok.Line, functionTok.Column, "dot requires matching vector dimensions.");

            var l = ToVector(left);
            var r = ToVector(right);

            if (functionTok.Value == "dot")
            {
                var result = l.Select((value, index) => value * r[index]).Sum();
                return new ExprResult("double", FormatNumber(result, "double"), $"dot({left.Repr},{right.Repr})");
            }

            if (functionTok.Value == "cross")
            {
                if (left.Type != "vec3" || right.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S105", functionTok.Line, functionTok.Column, "cross requires vec3 operands.");
                var result = new[]
                {
                    l[1] * r[2] - l[2] * r[1],
                    l[2] * r[0] - l[0] * r[2],
                    l[0] * r[1] - l[1] * r[0],
                };
                return new ExprResult("vec3", FormatVector(result), $"cross({left.Repr},{right.Repr})");
            }

            throw new CompileError("SEMANTIC", "S102", functionTok.Line, functionTok.Column, $"Unknown vector math function \"{functionTok.Value}\".");
        }

        ExprResult ApplyQuaternionRotateVector(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("vector", "P154", "Expected vector after rotate.");
            var vector = ParseAddExpression(legacyQuotedStrings);
            if (vector.Type != "vec3")
                throw new CompileError("SEMANTIC", "S154", functionTok.Line, functionTok.Column, "rotate vector requires vec3 value.");
            ExpectWord("by", "P155", "Expected by in rotate vector expression.");
            var quat = ParseAddExpression(legacyQuotedStrings);
            if (quat.Type != "quat")
                throw new CompileError("SEMANTIC", "S154", functionTok.Line, functionTok.Column, "rotate vector requires quaternion operand.");
            var result = RotateVectorByQuaternion(ToVector(vector), ToQuaternion(quat));
            return new ExprResult("vec3", FormatVector(result), $"rotate_vector({vector.Repr},{quat.Repr})");
        }

        ExprResult ApplyQuaternionSlerp(Token functionTok, ExprResult a, ExprResult b, ExprResult t)
        {
            if (a.Type != "quat" || b.Type != "quat")
                throw new CompileError("SEMANTIC", "S153", functionTok.Line, functionTok.Column, "slerp requires quaternion operands.");
            if (!IsNumeric(t.Type))
                throw new CompileError("SEMANTIC", "S153", functionTok.Line, functionTok.Column, "slerp t must be numeric.");
            var result = SlerpQuaternion(ToQuaternion(a), ToQuaternion(b), ToNumber(t));
            return new ExprResult("quat", FormatQuaternion(result), $"slerp({a.Repr},{b.Repr},{t.Repr})");
        }

        ExprResult ApplyEulerFromQuat(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("from", "P156", "Expected from after euler.");
            ExpectWord("quat", "P157", "Expected quat after euler from.");
            var quat = ParseAddExpression(legacyQuotedStrings);
            if (quat.Type != "quat")
                throw new CompileError("SEMANTIC", "S155", functionTok.Line, functionTok.Column, "euler from quat requires quaternion operand.");
            return new ExprResult("vec3", FormatVector(EulerFromQuaternion(ToQuaternion(quat))), $"euler_from_quat({quat.Repr})");
        }

        ExprResult ParseComplexFunction(bool legacyQuotedStrings)
        {
            var functionTok = Advance();
            var value = ParseUnaryExpression(legacyQuotedStrings);
            if (value.Type != "complex" && !IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S170", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires a complex operand.");
            var c = ToComplex(value);
            var result = functionTok.Value switch
            {
                "real" => c.R,
                "imag" => c.I,
                "magnitude" => Math.Sqrt(c.R * c.R + c.I * c.I),
                "phase" => Math.Atan2(c.I, c.R),
                _ => throw new CompileError("SEMANTIC", "S170", functionTok.Line, functionTok.Column, $"Unknown complex function {functionTok.Value}.")
            };
            return new ExprResult("double", FormatNumber(result, "double"), $"{functionTok.Value}({value.Repr})");
        }

        ExprResult ParseGeometryFunction(bool legacyQuotedStrings)
        {
            var functionTok = Advance();
            return functionTok.Value switch
            {
                "point" => ApplyPointInside(functionTok, legacyQuotedStrings),
                "rect" => ApplyRectIntersects(functionTok, legacyQuotedStrings),
                "closest" => ApplyClosestPoint(functionTok, legacyQuotedStrings),
                _ => throw new CompileError("SEMANTIC", "S160", functionTok.Line, functionTok.Column, $"Unknown geometry function {functionTok.Value}.")
            };
        }

        ExprResult ApplyPointInside(Token functionTok, bool legacyQuotedStrings)
        {
            var point = ParseAddExpression(legacyQuotedStrings);
            if (point.Type != "vec2")
                throw new CompileError("SEMANTIC", "S164", functionTok.Line, functionTok.Column, "point inside requires vec2 point.");
            ExpectWord("inside", "P165", "Expected inside in point inside expression.");
            var shape = ParseAddExpression(legacyQuotedStrings);
            var p = ToVector(point);
            var inside = shape.Type switch
            {
                "rect" => PointInsideRect(p, ToRect(shape)),
                "circle" => PointInsideCircle(p, ToCircle(shape)),
                _ => throw new CompileError("SEMANTIC", "S164", functionTok.Line, functionTok.Column, "point inside requires rect or circle shape.")
            };
            return new ExprResult("bool", inside.ToString().ToLowerInvariant(), $"point_inside({point.Repr},{shape.Repr})");
        }

        ExprResult ApplyRectIntersects(Token functionTok, bool legacyQuotedStrings)
        {
            var left = ParseAddExpression(legacyQuotedStrings);
            if (left.Type != "rect")
                throw new CompileError("SEMANTIC", "S165", functionTok.Line, functionTok.Column, "rect intersects requires rect operand.");
            ExpectWord("intersects", "P166", "Expected intersects in rect expression.");
            var right = ParseAddExpression(legacyQuotedStrings);
            if (right.Type != "rect")
                throw new CompileError("SEMANTIC", "S165", functionTok.Line, functionTok.Column, "rect intersects requires another rect.");
            var hit = RectIntersects(ToRect(left), ToRect(right));
            return new ExprResult("bool", hit.ToString().ToLowerInvariant(), $"rect_intersects({left.Repr},{right.Repr})");
        }

        ExprResult ApplyClosestPoint(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("point", "P167", "Expected point after closest.");
            ExpectWord("on", "P168", "Expected on after closest point.");
            if (CurrentWordIs("rect"))
            {
                Advance();
                var rect = ParseAddExpression(legacyQuotedStrings);
                if (rect.Type != "rect")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point on rect requires rect operand.");
                ExpectWord("to", "P169", "Expected to in closest point expression.");
                var point = ParseAddExpression(legacyQuotedStrings);
                if (point.Type != "vec2")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point target must be vec2.");
                return new ExprResult("vec2", FormatVector(ClosestPointOnRect(ToRect(rect), ToVector(point))), $"closest_rect({rect.Repr},{point.Repr})");
            }
            if (CurrentWordIs("circle"))
            {
                Advance();
                var circle = ParseAddExpression(legacyQuotedStrings);
                if (circle.Type != "circle")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point on circle requires circle operand.");
                ExpectWord("to", "P169", "Expected to in closest point expression.");
                var point = ParseAddExpression(legacyQuotedStrings);
                if (point.Type != "vec2")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point target must be vec2.");
                return new ExprResult("vec2", FormatVector(ClosestPointOnCircle(ToCircle(circle), ToVector(point))), $"closest_circle({circle.Repr},{point.Repr})");
            }
            throw new CompileError("PARSE", "P168", Current.Line, Current.Column, "Expected rect or circle after closest point on.");
        }

        static bool PointInsideRect(double[] point, (double X, double Y, double W, double H) rect)
            => point[0] >= rect.X && point[0] <= rect.X + rect.W && point[1] >= rect.Y && point[1] <= rect.Y + rect.H;

        static bool PointInsideCircle(double[] point, (double X, double Y, double R) circle)
        {
            var dx = point[0] - circle.X;
            var dy = point[1] - circle.Y;
            return dx * dx + dy * dy <= circle.R * circle.R + 0.0000000001;
        }

        static bool RectIntersects((double X, double Y, double W, double H) a, (double X, double Y, double W, double H) b)
            => a.X <= b.X + b.W && a.X + a.W >= b.X && a.Y <= b.Y + b.H && a.Y + a.H >= b.Y;

        static double[] ClosestPointOnRect((double X, double Y, double W, double H) rect, double[] point)
            => new[] { Math.Min(Math.Max(point[0], rect.X), rect.X + rect.W), Math.Min(Math.Max(point[1], rect.Y), rect.Y + rect.H) };

        static double[] ClosestPointOnCircle((double X, double Y, double R) circle, double[] point)
        {
            var dx = point[0] - circle.X;
            var dy = point[1] - circle.Y;
            var len = Math.Sqrt(dx * dx + dy * dy);
            if (Math.Abs(len) < 0.0000000001)
                return new[] { circle.X + circle.R, circle.Y };
            return new[] { circle.X + dx / len * circle.R, circle.Y + dy / len * circle.R };
        }

        ExprResult ParseAdvancedMathFunction(bool legacyQuotedStrings)
        {
            var functionTok = Advance();
            switch (functionTok.Value)
            {
                case "saturate":
                case "sign":
                case "fract":
                    return ApplyAdvancedScalarUnary(functionTok, ParseUnaryExpression(legacyQuotedStrings));
                case "step":
                {
                    var edge = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between step arguments");
                    var value = ParseAddExpression(legacyQuotedStrings);
                    return ApplyStepFunction(functionTok, edge, value);
                }
                case "smoothstep":
                {
                    var edge0 = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between smoothstep arguments");
                    var edge1 = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between smoothstep arguments");
                    var value = ParseAddExpression(legacyQuotedStrings);
                    return ApplySmoothStepFunction(functionTok, edge0, edge1, value);
                }
                case "inverse":
                {
                    ExpectWord("lerp", "P122", "Expected lerp after inverse.");
                    var a = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between inverse lerp arguments");
                    var b = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between inverse lerp arguments");
                    var value = ParseAddExpression(legacyQuotedStrings);
                    return ApplyInverseLerpFunction(functionTok, a, b, value);
                }
                case "remap":
                {
                    var value = ParseAddExpression(legacyQuotedStrings);
                    ExpectWord("from", "P123", "Expected from in remap expression.");
                    var inMin = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between remap input range values");
                    var inMax = ParseAddExpression(legacyQuotedStrings);
                    ExpectWord("to", "P124", "Expected to in remap expression.");
                    var outMin = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between remap output range values");
                    var outMax = ParseAddExpression(legacyQuotedStrings);
                    return ApplyRemapFunction(functionTok, value, inMin, inMax, outMin, outMax);
                }
                case "lerp":
                {
                    var a = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between lerp arguments");
                    var b = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between lerp arguments");
                    var t = ParseAddExpression(legacyQuotedStrings);
                    return ApplyLerpFunction(functionTok, a, b, t);
                }
                case "distance":
                {
                    var a = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between distance arguments");
                    var b = ParseAddExpression(legacyQuotedStrings);
                    return ApplyDistanceFunction(functionTok, a, b);
                }
                case "reflect":
                {
                    var dir = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between reflect arguments");
                    var normal = ParseAddExpression(legacyQuotedStrings);
                    return ApplyReflectFunction(functionTok, dir, normal);
                }
                case "project":
                {
                    var value = ParseAddExpression(legacyQuotedStrings);
                    ExpectWord("onto", "P125", "Expected onto in project expression.");
                    var onto = ParseAddExpression(legacyQuotedStrings);
                    return ApplyProjectFunction(functionTok, value, onto);
                }
                case "clamp":
                {
                    if (CurrentWordIs("length"))
                    {
                        Advance();
                        var value = ParseAddExpression(legacyQuotedStrings);
                        ExpectWord("to", "P126", "Expected to in clamp length expression.");
                        var max = ParseAddExpression(legacyQuotedStrings);
                        return ApplyClampLengthFunction(functionTok, value, max);
                    }
                    return ParseScalarMathFunctionStartingWith(functionTok, legacyQuotedStrings);
                }
                case "slerp":
                {
                    var a = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between slerp arguments");
                    var b = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between slerp arguments");
                    var t = ParseAddExpression(legacyQuotedStrings);
                    return ApplyQuaternionSlerp(functionTok, a, b, t);
                }
                case "euler":
                    return ApplyEulerFromQuat(functionTok, legacyQuotedStrings);
                case "rotate":
                    if (CurrentWordIs("vector"))
                        return ApplyQuaternionRotateVector(functionTok, legacyQuotedStrings);
                    return ApplyMatrixFunction(functionTok);
                case "translate":
                case "scale":
                case "matmul":
                    return ApplyMatrixFunction(functionTok);
                case "compose":
                    return ApplyComposeTransform(functionTok);
                default:
                    throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, $"Unknown advanced math function \"{functionTok.Value}\".");
            }
        }

        ExprResult ParseScalarMathFunctionStartingWith(Token functionTok, bool legacyQuotedStrings)
        {
            if (functionTok.Value == "clamp")
            {
                var value = ParseAddExpression(legacyQuotedStrings);
                ExpectWord("between", "P120", "Expected word \"between\" in clamp expression.");
                var min = ParseAddExpression(legacyQuotedStrings);
                ExpectWord("and", "P121", "Expected word \"and\" in clamp expression.");
                var max = ParseAddExpression(legacyQuotedStrings);
                return ApplyClampFunction(functionTok, value, min, max);
            }
            throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"Unknown scalar math function \"{functionTok.Value}\".");
        }

        ExprResult ParseVectorMathFunction(bool legacyQuotedStrings)
        {
            var functionTok = Advance();
            if (IsVectorBinaryFunctionName(functionTok.Value))
            {
                var left = ParseAddExpression(legacyQuotedStrings);
                Expect("COMMA", "comma between vector math arguments");
                var right = ParseAddExpression(legacyQuotedStrings);
                return ApplyVectorBinaryFunction(functionTok, left, right);
            }

            if (IsVectorUnaryFunctionName(functionTok.Value))
            {
                var value = ParseUnaryExpression(legacyQuotedStrings);
                return ApplyVectorUnaryFunction(functionTok, value);
            }

            throw new CompileError("SEMANTIC", "S102", functionTok.Line, functionTok.Column, $"Unknown vector math function \"{functionTok.Value}\".");
        }

        ExprResult ParseScalarMathFunction(bool legacyQuotedStrings)
        {
            var functionTok = Advance();
            if (functionTok.Value == "clamp")
            {
                var value = ParseAddExpression(legacyQuotedStrings);
                ExpectWord("between", "P120", "Expected word \"between\" in clamp expression.");
                var min = ParseAddExpression(legacyQuotedStrings);
                ExpectWord("and", "P121", "Expected word \"and\" in clamp expression.");
                var max = ParseAddExpression(legacyQuotedStrings);
                return ApplyClampFunction(functionTok, value, min, max);
            }

            if (IsScalarBinaryFunctionName(functionTok.Value))
            {
                var left = ParseAddExpression(legacyQuotedStrings);
                Expect("COMMA", "comma between scalar math arguments");
                var right = ParseAddExpression(legacyQuotedStrings);
                return ApplyScalarBinaryFunction(functionTok, left, right);
            }

            if (IsScalarUnaryFunctionName(functionTok.Value))
            {
                var value = ParseUnaryExpression(legacyQuotedStrings);
                return ApplyScalarUnaryFunction(functionTok, value);
            }

            throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"Unknown scalar math function \"{functionTok.Value}\".");
        }

        void ParseRename()
        {
            ExpectKeyword("rename");
            var oldTok = Expect("STRING", "old symbol name");
            if (!IsKeyword("to"))
                throw new CompileError("PARSE", "P074", Current.Line, Current.Column, "Expected keyword \"to\" after old symbol name.");
            ExpectKeyword("to");
            var newTok = Expect("STRING", "new symbol name");

            RenameSymbol(oldTok, newTok);
            ExpectLine();
        }

        void CheckDuplicateSymbol(Token nameTok, string label)
        {
            if (SymbolExists(nameTok.Value))
                throw new CompileError("SEMANTIC", "S001", nameTok.Line, nameTok.Column, $"{label} \"{nameTok.Value}\" is already defined.");
        }

        bool SymbolExists(string name) => _vars.ContainsKey(name);

        VarInfo ResolveSymbol(Token token, string code, string message)
        {
            if (_vars.TryGetValue(token.Value, out var info))
                return info;
            throw new CompileError("SEMANTIC", code, token.Line, token.Column, message);
        }

        VarInfo ResolveSymbol(Token token, string code, Func<string, string> message)
            => ResolveSymbol(token, code, message(token.Value));

        ExprResult FormatSymbolForOutput(Token token, string code = "S036")
        {
            if (!SymbolExists(token.Value) && token.Value.Contains('.', StringComparison.Ordinal))
            {
                var component = FormatComponentReference(token);
                return new ExprResult("text", component.Value, component.Repr);
            }
            var info = ResolveSymbol(token, code, name => $"Unknown symbol \"{name}\".");
            return new ExprResult("text", info.Value, $"symbol({token.Value})");
        }

        ExprResult FormatVariableReference(Token token, string code, Func<string, string> message)
        {
            var info = ResolveSymbol(token, code, message);
            return new ExprResult(info.Type, info.Value, $"var({token.Value})");
        }

        void DefineSymbol(string name, string type, string value, bool isConst = false)
        {
            _vars[name] = new VarInfo(type, value, isConst);
            _varList.Add((name, isConst ? $"const {type}" : type, value));
        }

        void DefineRuntimeSymbol(string name, string type, string value, bool isConst = false)
        {
            _vars[name] = new VarInfo(type, value, isConst, IsRuntime: true);
            _runtimeSymbols.Add(name);
            _varList.Add((name, isConst ? $"const {type}" : type, value));
        }

        void RenameSymbol(Token oldTok, Token newTok)
        {
            var info = ResolveSymbol(oldTok, "S034", name => $"Cannot rename missing symbol \"{name}\".");
            if (info.IsConst)
                throw new CompileError("SEMANTIC", "S039", oldTok.Line, oldTok.Column, $"Cannot rename const symbol \"{oldTok.Value}\".");
            if (SymbolExists(newTok.Value))
                throw new CompileError("SEMANTIC", "S035", newTok.Line, newTok.Column, $"Cannot rename to existing symbol \"{newTok.Value}\".");

            _vars.Remove(oldTok.Value);
            _vars[newTok.Value] = info;
            for (var i = 0; i < _varList.Count; i++)
            {
                if (_varList[i].Name == oldTok.Value)
                {
                    _varList[i] = (newTok.Value, info.IsConst ? $"const {info.Type}" : info.Type, info.Value);
                    break;
                }
            }
        }

        void SetSymbolValue(Token target, ExprResult value)
        {
            if (!SymbolExists(target.Value) && target.Value.Contains('.', StringComparison.Ordinal))
            {
                SetVectorComponentValue(target, value);
                return;
            }

            var current = ResolveSymbol(target, "S052", name => $"Cannot set missing symbol \"{name}\".");
            if (current.IsConst)
                throw new CompileError("SEMANTIC", "S053", target.Line, target.Column, $"Cannot set const symbol \"{target.Value}\".");
            if (current.Type == "int" && IsNumeric(value.Type) && Math.Abs(ToNumber(value) - Math.Round(ToNumber(value))) > 0.0000000001)
                throw new CompileError("SEMANTIC", "S054", target.Line, target.Column, $"Cannot assign {value.Type} to {current.Type} symbol \"{target.Value}\".");
            if (!CanAssign(current.Type, value.Type))
                throw new CompileError("SEMANTIC", "S054", target.Line, target.Column, $"Cannot assign {value.Type} to {current.Type} symbol \"{target.Value}\".");

            var finalValue = CoerceValue(value, current.Type);
            _vars[target.Value] = current with { Value = finalValue };
            UpdateVarList(target.Value, current.Type, finalValue, current.IsConst);
        }

        void SetVectorComponentValue(Token target, ExprResult value)
        {
            if (!TrySplitComponentName(target.Value, out var symbolName, out var component))
                throw new CompileError("SEMANTIC", "S108", target.Line, target.Column, $"Invalid component target \"{target.Value}\".");

            var baseToken = target with { Value = symbolName };
            var current = ResolveSymbol(baseToken, "S108", name => $"Cannot set missing component base symbol \"{name}\".");
            if (current.IsConst)
                throw new CompileError("SEMANTIC", "S053", target.Line, target.Column, $"Cannot set const symbol \"{symbolName}\".");
            if (!IsVector(current.Type))
                throw new CompileError("SEMANTIC", "S108", target.Line, target.Column, "Component assignment requires vector symbol.");
            if (!IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S109", target.Line, target.Column, "Vector component assignment requires numeric value.");

            var index = VectorComponentIndex(current.Type, component);
            if (index < 0)
                throw new CompileError("SEMANTIC", "S108", target.Line, target.Column, $"Vector {current.Type} does not have component \"{component}\".");

            var values = ToVector(new ExprResult(current.Type, current.Value, $"symbol({symbolName})"));
            values[index] = ToNumber(value);
            var finalValue = FormatVector(values);
            _vars[symbolName] = current with { Value = finalValue };
            UpdateVarList(symbolName, current.Type, finalValue, current.IsConst);
        }

        void ApplyNumericUpdate(Token target, ExprResult value, string op)
        {
            var current = ResolveSymbol(target, "S052", name => $"Cannot update missing symbol \"{name}\".");
            if (current.IsConst)
                throw new CompileError("SEMANTIC", "S053", target.Line, target.Column, $"Cannot update const symbol \"{target.Value}\".");
            if (!IsNumeric(current.Type) || !IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S044", target.Line, target.Column, "Quick math update requires numeric operands.");

            var result = ApplyNumericBinary(op, new ExprResult(current.Type, current.Value, $"symbol({target.Value})"), value);
            SetSymbolValue(target, result);
        }

        static bool CanAssign(string targetType, string valueType)
        {
            if (targetType == valueType)
                return true;
            if (IsVector(targetType) || IsVector(valueType))
                return false;
            if (IsMatrixType(targetType) || IsMatrixType(valueType))
                return false;
            if (IsQuaternion(targetType) || IsQuaternion(valueType))
                return false;
            if (IsGeometryType(targetType) || IsGeometryType(valueType))
                return false;
            if (IsComplex(targetType) || IsComplex(valueType))
                return false;
            return targetType switch
            {
                "int" => IsNumeric(valueType),
                "float" => valueType is "int" or "double",
                "double" => valueType is "int" or "float",
                _ => false,
            };
        }

        static string CoerceValue(ExprResult value, string targetType)
        {
            if (IsVector(targetType) || IsMatrixType(targetType) || IsQuaternion(targetType) || IsGeometryType(targetType) || IsComplex(targetType) || IsColor(targetType) || IsAngle(targetType))
                return value.Value;
            if (!IsNumeric(targetType))
                return value.Value;
            return FormatNumber(ToNumber(value), targetType);
        }

        void UpdateVarList(string name, string type, string value, bool isConst)
        {
            for (var i = 0; i < _varList.Count; i++)
            {
                if (_varList[i].Name == name)
                {
                    _varList[i] = (name, isConst ? $"const {type}" : type, value);
                    return;
                }
            }
        }

        List<Token> ReadUntilLine()
        {
            var result = new List<Token>();
            while (!CurrentIs("NEWLINE") && !CurrentIs("EOF"))
                result.Add(Advance());
            ExpectLine();
            return result;
        }

        List<Token> ReadBlock(string endKeyword, string missingCode, string missingMessage)
        {
            var result = new List<Token>();
            while (!CurrentIs("EOF"))
            {
                if (IsKeyword("end") && PeekKeyword(endKeyword))
                {
                    ExpectKeyword("end");
                    ExpectKeyword(endKeyword);
                    ExpectLine();
                    return result;
                }
                result.Add(Advance());
            }
            throw new CompileError("PARSE", missingCode, Current.Line, Current.Column, missingMessage);
        }

        bool EvaluateConditionTokens(List<Token> conditionTokens)
        {
            var savedTokens = _tokens;
            var savedPos = _pos;
            _tokens = WithEof(conditionTokens);
            _pos = 0;
            try
            {
                var condition = ParseCondition();
                Expect("EOF", "end of condition");
                return condition.Value;
            }
            finally
            {
                _tokens = savedTokens;
                _pos = savedPos;
            }
        }

        void RunTokenBlock(List<Token> body)
        {
            var savedTokens = _tokens;
            var savedPos = _pos;
            _tokens = WithEof(body);
            _pos = 0;
            try
            {
                SkipNewlines();
                while (!CurrentIs("EOF"))
                {
                    ParseStatement(apply: true, inIf: false);
                    SkipNewlines();
                }
            }
            finally
            {
                _tokens = savedTokens;
                _pos = savedPos;
            }
        }

        static List<Token> WithEof(List<Token> tokens)
        {
            var copy = new List<Token>(tokens);
            var last = copy.Count > 0 ? copy[^1] : new Token("EOF", "", 0, 0);
            copy.Add(new Token("EOF", "", last.Line, last.Column));
            return copy;
        }

        CompareResult ParseComparison() => ParseCondition();

        CompareResult ParseCondition()
        {
            var saved = _parsingCondition;
            _parsingCondition = true;
            ExprResult expr;
            try
            {
                expr = ParseOrExpression();
            }
            finally
            {
                _parsingCondition = saved;
            }
            if (expr.Type != "bool")
                throw new CompileError("SEMANTIC", "S040", Current.Line, Current.Column, "Condition must evaluate to bool.");
            if (!IsConditionExpression(expr))
                throw new CompileError("PARSE", "P052", Current.Line, Current.Column, "Invalid comparison expression. Expected \"is\".");
            return new CompareResult(expr.Value == "true", expr.Repr);
        }

        static bool IsConditionExpression(ExprResult expr)
            => expr.Repr.StartsWith("COMPARE_", StringComparison.Ordinal) ||
               expr.Repr.StartsWith("cmp(", StringComparison.Ordinal) ||
               expr.Repr.StartsWith("and(", StringComparison.Ordinal) ||
               expr.Repr.StartsWith("or(", StringComparison.Ordinal) ||
               expr.Repr.StartsWith("not(", StringComparison.Ordinal);

        ExprResult ParseOrExpression()
        {
            var left = ParseAndExpression();
            while (IsKeyword("or"))
            {
                ExpectKeyword("or");
                var right = ParseAndExpression();
                left = ApplyLogical("or", left, right);
            }
            return left;
        }

        ExprResult ParseAndExpression()
        {
            var left = ParseNotExpression();
            while (IsKeyword("and"))
            {
                ExpectKeyword("and");
                var right = ParseNotExpression();
                left = ApplyLogical("and", left, right);
            }
            return left;
        }

        ExprResult ParseNotExpression()
        {
            if (IsKeyword("not"))
            {
                ExpectKeyword("not");
                var value = ParseNotExpression();
                if (value.Type != "bool")
                    throw new CompileError("SEMANTIC", "S041", Current.Line, Current.Column, "not requires a bool operand.");
                return new ExprResult("bool", value.Value == "true" ? "false" : "true", $"not({value.Repr})");
            }
            return ParseComparisonExpression();
        }

        ExprResult ParseComparisonExpression()
        {
            var left = ParseAddExpression();

            if (IsKeyword("is"))
            {
                ExpectKeyword("is");
                var isNot = false;
                if (IsKeyword("not"))
                {
                    isNot = true;
                    ExpectKeyword("not");
                }
                if (IsExpressionEnd())
                    throw new CompileError("PARSE", isNot ? "P051" : "P050", Current.Line, Current.Column, isNot ? "Expected right operand after \"is not\"." : "Expected right operand after \"is\".");
                var right = ParseAddExpression(legacyQuotedStrings: true);
                if (left.Type != right.Type)
                    throw new CompileError("SEMANTIC", "S021", Current.Line, Current.Column, $"Comparison type mismatch: {left.Type} and {right.Type}.");
                var equal = string.Equals(left.Value, right.Value, StringComparison.Ordinal);
                var value = isNot ? !equal : equal;
                var op = isNot ? "COMPARE_IS_NOT" : "COMPARE_IS";
                return new ExprResult("bool", value.ToString().ToLowerInvariant(), $"{op}|left={left.Repr}|right={right.Repr}");
            }

            if (CurrentIs("GT") || CurrentIs("GTE") || CurrentIs("LT") || CurrentIs("LTE"))
            {
                var opTok = Advance();
                var right = ParseAddExpression();
                if (!IsNumeric(left.Type) || !IsNumeric(right.Type))
                    throw new CompileError("SEMANTIC", "S042", opTok.Line, opTok.Column, "Numeric comparison requires numeric operands.");
                var leftNum = ToNumber(left);
                var rightNum = ToNumber(right);
                var value = opTok.Type switch
                {
                    "GT" => leftNum > rightNum,
                    "GTE" => leftNum >= rightNum,
                    "LT" => leftNum < rightNum,
                    _ => leftNum <= rightNum,
                };
                return new ExprResult("bool", value.ToString().ToLowerInvariant(), $"cmp({opTok.Value},{left.Repr},{right.Repr})");
            }

            return left;
        }

        record CommandExpr(string Value, string Repr, string Command);
        record StatementRule(Func<bool> Matches, Action<bool, bool> Parse);

        ExprResult ParseExpression(string context, string missingCode, string missingMessage)
        {
            if (IsExpressionEnd())
                throw new CompileError("PARSE", missingCode, Current.Line, Current.Column, missingMessage);

            var expr = ParseAddExpression(legacyQuotedStrings: true);
            if (expr.Type != "text")
                throw new CompileError("SEMANTIC", expr.Type == "bool" ? "S011" : "S012", Current.Line, Current.Column, $"{context} requires text expression.");
            return expr;
        }

        ExprResult ParseTextLikeExpression(string context, string missingCode, string missingMessage)
        {
            if (IsExpressionEnd())
                throw new CompileError("PARSE", missingCode, Current.Line, Current.Column, missingMessage);

            if (context == "show")
                return ParsePrintValueExpression();

            if (CurrentIs("STRING") && !PeekType("PLUS"))
            {
                var t = Advance();
                if (SymbolExists(t.Value))
                    return FormatSymbolForOutput(t);
                if (IsSymbolName(t.Value))
                    throw new CompileError("SEMANTIC", "S036", t.Line, t.Column, $"Unknown symbol \"{t.Value}\".");
                return new ExprResult("text", t.Value, $"str(\"{t.Value}\")");
            }

            var expr = ParseAddExpression(legacyQuotedStrings: true);
            if (expr.Type != "text")
                throw new CompileError("SEMANTIC", "S012", Current.Line, Current.Column, $"{context} requires text expression.");
            return expr;
        }

        ExprResult ParsePrintValueExpression()
        {
            if (IsKeyword("string"))
                return ParseAddExpression(legacyQuotedStrings: false);
            if (CurrentIs("STRING") && !PeekType("PLUS"))
            {
                var t = Advance();
                return FormatSymbolForOutput(t);
            }
            return ParseAddExpression(legacyQuotedStrings: false);
        }

        ExprResult ParseAddExpression(bool legacyQuotedStrings = false)
        {
            var left = ParseMultiplyExpression(legacyQuotedStrings);
            while (CurrentIs("PLUS") || CurrentIs("MINUS"))
            {
                var op = Advance();
                if (IsExpressionEnd())
                    throw new CompileError("PARSE", "P011", Current.Line, Current.Column, "Expected expression after operator.");
                var right = ParseMultiplyExpression(legacyQuotedStrings);
                left = op.Type == "PLUS" ? ApplyPlus(left, right) : ApplyNumericBinary("-", left, right);
            }
            return left;
        }

        ExprResult ParseMultiplyExpression(bool legacyQuotedStrings)
        {
            var left = ParsePowerExpression(legacyQuotedStrings);
            while (CurrentIs("STAR") || CurrentIs("SLASH") || CurrentIs("PERCENT"))
            {
                var op = Advance();
                if (IsExpressionEnd())
                    throw new CompileError("PARSE", "P011", Current.Line, Current.Column, "Expected expression after operator.");
                var right = ParsePowerExpression(legacyQuotedStrings);
                left = ApplyNumericBinary(op.Value, left, right);
            }
            return left;
        }

        ExprResult ParsePowerExpression(bool legacyQuotedStrings)
        {
            var left = ParseUnaryExpression(legacyQuotedStrings);
            if (CurrentIs("CARET"))
            {
                Advance();
                var right = ParsePowerExpression(legacyQuotedStrings);
                left = ApplyNumericBinary("^", left, right);
            }
            return left;
        }

        ExprResult ParseUnaryExpression(bool legacyQuotedStrings)
        {
            if (CurrentIs("MINUS"))
            {
                Advance();
                var value = ParseUnaryExpression(legacyQuotedStrings);
                if (IsComplex(value.Type))
                {
                    var c = ToComplex(value);
                    return new ExprResult("complex", FormatComplex(-c.R, -c.I), $"neg({value.Repr})");
                }
                if (!IsNumeric(value.Type))
                    throw new CompileError("SEMANTIC", "S043", Current.Line, Current.Column, "Unary minus requires numeric or complex operand.");
                var type = value.Type;
                var num = -ToNumber(value);
                return new ExprResult(type, FormatNumber(num, type), $"neg({value.Repr})");
            }

            if (CurrentWordIs("transform"))
                return ApplyTransformFunction(Advance());

            if ((CurrentIs("IDENT") || CurrentIs("KEYWORD")) && IsComplexFunctionName(Current.Value))
                return ParseComplexFunction(legacyQuotedStrings);

            if ((CurrentIs("IDENT") || CurrentIs("KEYWORD")) && IsGeometryFunctionName(Current.Value))
                return ParseGeometryFunction(legacyQuotedStrings);

            if ((CurrentIs("IDENT") || CurrentIs("KEYWORD")) && IsAdvancedMathFunctionName(Current.Value))
                return ParseAdvancedMathFunction(legacyQuotedStrings);

            if ((CurrentIs("IDENT") || CurrentIs("KEYWORD")) && (IsScalarUnaryFunctionName(Current.Value) || IsScalarBinaryFunctionName(Current.Value) || Current.Value == "clamp"))
                return ParseScalarMathFunction(legacyQuotedStrings);

            if ((CurrentIs("IDENT") || CurrentIs("KEYWORD")) && (IsVectorUnaryFunctionName(Current.Value) || IsVectorBinaryFunctionName(Current.Value)))
                return ParseVectorMathFunction(legacyQuotedStrings);

            return ParsePrimaryExpression(legacyQuotedStrings);
        }

        ExprResult ParseVectorLiteral(bool legacyQuotedStrings)
        {
            var startTok = Expect("LBRACKET", "vector literal start");
            var values = new List<double>();

            if (CurrentIs("RBRACKET"))
                throw new CompileError("SEMANTIC", "S106", startTok.Line, startTok.Column, "Vector literal cannot be empty.");

            while (true)
            {
                var component = ParseAddExpression(legacyQuotedStrings);
                if (!IsNumeric(component.Type))
                    throw new CompileError("SEMANTIC", "S107", startTok.Line, startTok.Column, "Vector literal components must be numeric.");
                values.Add(ToNumber(component));

                if (CurrentIs("COMMA"))
                {
                    Advance();
                    if (CurrentIs("RBRACKET"))
                        throw new CompileError("PARSE", "P130", Current.Line, Current.Column, "Expected vector component after comma.");
                    continue;
                }

                break;
            }

            Expect("RBRACKET", "vector literal end");
            var type = VectorTypeForCount(values.Count);
            if (string.IsNullOrEmpty(type))
                throw new CompileError("SEMANTIC", "S106", startTok.Line, startTok.Column, "Vector literal must have 2, 3, or 4 components.");
            return new ExprResult(type, FormatVector(values.ToArray()), $"{type}({FormatVector(values.ToArray())})");
        }

        ExprResult ParsePrimaryExpression(bool legacyQuotedStrings)
        {
            if (IsKeyword("string"))
                return ParseCanonicalStringLiteral();

            if (IsKeyword("color"))
                return ParseColorLiteralExpression();

            if (CurrentWordIs("complex"))
                return ParseComplexLiteral();

            if (CurrentWordIs("quat"))
                return ParseQuaternionLiteral();

            if (CurrentWordIs("rect"))
                return ParseRectLiteral();

            if (CurrentWordIs("circle"))
                return ParseCircleLiteral();

            if (CurrentIs("LPAREN"))
            {
                Advance();
                var expr = ParseOrExpression();
                Expect("RPAREN", "closing parenthesis");
                return expr;
            }

            if (CurrentIs("LBRACKET"))
                return ParseVectorLiteral(legacyQuotedStrings);

if (CurrentIs("STRING"))
{
    var t = Advance();
    if (legacyQuotedStrings)
        return new ExprResult("text", t.Value, $"str(\"{t.Value}\")");
    if (SymbolExists(t.Value) || t.Value.Contains('.', StringComparison.Ordinal))
        return FormatSymbolReference(t);
    throw new CompileError("SEMANTIC", "S036", t.Line, t.Column, $"Unknown symbol \"{t.Value}\".");
}

            if (CurrentIs("IDENT"))
            {
                var t = Advance();
                if (IsMathConstantName(t.Value) && !SymbolExists(t.Value))
                {
                    var value = t.Value == "pi" ? Math.PI : Math.E;
                    return new ExprResult("double", FormatNumber(value, "double"), $"const({t.Value})");
                }
                return FormatVariableReference(t, _parsingCondition ? "S020" : "S010", name => _parsingCondition ? $"Unknown variable \"{name}\" in comparison." : $"Unknown variable \"{name}\".");
            }

            if (CurrentIs("INT") || CurrentIs("DECIMAL"))
                return ParseNumberMaybeAngleLiteral();

            if (CurrentIs("BOOL"))
                return ParseBoolLiteral();

            throw new CompileError("PARSE", "P010", Current.Line, Current.Column, "Expected expression.");
        }

        string ExpectName(string what)
        {
            if (CurrentIs("STRING") || CurrentIs("IDENT"))
                return Advance().Value;
            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, $"Expected {what}.");
        }

        bool CurrentWordIs(string value)
            => (Current.Type == "KEYWORD" || Current.Type == "IDENT") && Current.Value == value;

        void ExpectWord(string value, string code, string message)
        {
            if ((Current.Type == "KEYWORD" || Current.Type == "IDENT") && Current.Value == value)
            {
                Advance();
                return;
            }
            throw new CompileError("PARSE", code, Current.Line, Current.Column, message);
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
        bool IsExpressionEnd() => CurrentIs("NEWLINE") || CurrentIs("EOF") || CurrentIs("RPAREN") || CurrentIs("RBRACKET") || IsKeyword("to") || IsKeyword("from") || IsKeyword("by") || IsKeyword("else") || IsKeyword("end");
        static bool IsSymbolName(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
                return false;
            if (!(char.IsLetter(value[0]) || value[0] == '_'))
                return false;
            for (var i = 1; i < value.Length; i++)
                if (!(char.IsLetterOrDigit(value[i]) || value[i] == '_'))
                    return false;
            return true;
        }

        bool PeekKeyword(string value)
            => PeekKeyword(value, 1);

        bool PeekKeyword(string value, int offset)
        {
            var next = _pos + offset;
            return next < _tokens.Count && _tokens[next].Type == "KEYWORD" && _tokens[next].Value == value;
        }

        bool PeekType(string type)
        {
            var next = _pos + 1;
            return next < _tokens.Count && _tokens[next].Type == type;
        }

        bool IsKeyword(string value) => Current.Type == "KEYWORD" && Current.Value == value;
        bool CurrentIs(string type) => Current.Type == type;
        Token Current => _tokens[Math.Min(_pos, _tokens.Count - 1)];
        Token Advance() => _tokens[_pos++];
    }
}
