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
                else if (word is "program" or "let" or "be" or "title" or "message" or "text" or "show" or "set" or "to" or "exit" or "blend" or "mix" or "code" or "end" or "if" or "else" or "is" or "not" or "define" or "string" or "int" or "bool" or "var" or "called" or "rename" or "print" or "const" or "float" or "double" or "while" or "from" or "add" or "remove" or "multiply" or "by" or "divide" or "function" or "call" or "and" or "or" or "write" or "file" or "with" or "load")
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

    static byte[] BuildFileIoPe(IrModel ir)
    {
        const int sectionRaw = 0x200;
        const int sectionRva = 0x1000;
        const int sectionSize = 0xC000;
        const int importRva = 0x1800;
        const int iltRva = 0x1900;
        const int iatRva = 0x1940;
        const int dllNameRva = 0x1980;
        const int dataStartRva = 0x3000;
        const int slotLenStartRva = 0x8F00;
        const int slotStartRva = 0x9000;
        const int runtimeSlotBytes = 0x1000;

        var actions = OrderedActionMaps(ir);
        if (actions.Count == 0 || actions[^1].GetValueOrDefault("op") != "exit")
            throw new CompileError("BACKEND", "B001", 0, 0, "File I/O backend requires final exit action.");

        var pe = new byte[sectionRaw + sectionSize];
        WritePeHeader(pe, sectionSize, importRva, 0x600, subsystem: 3);

        var slotNames = actions
            .Where(a => a.GetValueOrDefault("value_kind") == "slot" || a.GetValueOrDefault("op") == "file_load" || a.GetValueOrDefault("op") == "print_runtime_slot")
            .Select(a => a.GetValueOrDefault("target") != "" ? a.GetValueOrDefault("target")! : a.GetValueOrDefault("value")!)
            .Where(s => !string.IsNullOrWhiteSpace(s))
            .Distinct(StringComparer.Ordinal)
            .ToList();
        var slots = new Dictionary<string, (int BufferRva, int LenRva)>(StringComparer.Ordinal);
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
        }

        var importNameCursor = 0x19A0;
        var imports = new[] { "CreateFileW", "WriteFile", "ReadFile", "CloseHandle", "SetFilePointer", "GetStdHandle", "ExitProcess" };
        for (var i = 0; i < imports.Length; i++)
        {
            AddImport(pe, iltRva, iatRva, i, importNameCursor, imports[i]);
            importNameCursor += 0x20;
        }
        WriteAscii(pe, RvaToRaw(dllNameRva), "kernel32.dll\0");
        var importRaw = RvaToRaw(importRva);
        WriteUInt32(pe, importRaw, iltRva);
        WriteUInt32(pe, importRaw + 12, dllNameRva);
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
            Lea(new byte[] { 0x4C, 0x8D, 0x0D }, slotLenStartRva - 8, 7);
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
            Lea(new byte[] { 0x4C, 0x8D, 0x0D }, slotLenStartRva - 8, 7);
            StoreStack32(0x20, 0);
            CallIat(1);
            CheckEaxZero();
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
                Emit(0x41, 0xB8); EmitUInt32(runtimeSlotBytes - 1);
                Lea(new byte[] { 0x4C, 0x8D, 0x0D }, slot.LenRva, 7);
                StoreStack32(0x20, 0);
                CallIat(2);
                CheckEaxZero();
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
        CallIat(6);
        var failRva = sectionRva + code.Count;
        Emit(0xB9, 0x01, 0x00, 0x00, 0x00);
        CallIat(6);
        foreach (var offsetPos in failJumps)
        {
            var nextRva = sectionRva + offsetPos + 4;
            var rel = failRva - nextRva;
            BitConverter.GetBytes(rel).CopyTo(code.ToArray(), offsetPos);
        }
        var codeBytes = code.ToArray();
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
            Array.Copy(bytes, 0, pe, RvaToRaw(rva), bytes.Length);
            dataCursor += Align(bytes.Length + 1, 8);
            return rva;
        }

        int AddUtf16(string value)
        {
            var bytes = Encoding.Unicode.GetBytes(value + "\0");
            var rva = dataCursor;
            Array.Copy(bytes, 0, pe, RvaToRaw(rva), bytes.Length);
            dataCursor += Align(bytes.Length, 8);
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
            op is "file_write" or "file_append" or "file_load" or "print_runtime_slot");

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
        readonly List<StatementRule> _statementRules;
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

            if (!CurrentIs("KEYWORD") || Current.Value is not ("string" or "int" or "float" or "double" or "bool" or "var"))
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

            var value = ParseCanonicalValue(declaredType.Value);
            DefineSymbol(nameTok.Value, value.Type, value.Value, isConst);
            ExpectLine();
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

            if (IsKeyword("string"))
                return ParseCanonicalStringLiteral();

            if (CurrentIs("INT"))
                return ParseIntLiteral();

            if (CurrentIs("DECIMAL"))
                return ParseNumericLiteral("double");

            if (CurrentIs("BOOL"))
                return ParseBoolLiteral();

            throw new CompileError("SEMANTIC", "S033", Current.Line, Current.Column, "define var requires string, int, or bool literal value.");
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

        ExprResult FormatSymbolReference(Token token)
        {
            var info = ResolveSymbol(token, "S036", name => $"Unknown symbol \"{name}\".");
            return new ExprResult(info.Type, info.Value, $"symbol({token.Value})");
        }

        static bool IsNumeric(string type) => type is "int" or "float" or "double";

        static double ToNumber(ExprResult expr)
            => double.Parse(expr.Value, CultureInfo.InvariantCulture);

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
            if (IsNumeric(left.Type) && IsNumeric(right.Type))
                return ApplyNumericBinary("+", left, right);
            throw new CompileError("SEMANTIC", "S011", Current.Line, Current.Column, "Type mismatch in expression.");
        }

        ExprResult ApplyNumericBinary(string op, ExprResult left, ExprResult right)
        {
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
                if (!IsNumeric(value.Type))
                    throw new CompileError("SEMANTIC", "S043", Current.Line, Current.Column, "Unary minus requires numeric operand.");
                var type = value.Type;
                var num = -ToNumber(value);
                return new ExprResult(type, FormatNumber(num, type), $"neg({value.Repr})");
            }
            return ParsePrimaryExpression(legacyQuotedStrings);
        }

        ExprResult ParsePrimaryExpression(bool legacyQuotedStrings)
        {
            if (IsKeyword("string"))
                return ParseCanonicalStringLiteral();

            if (CurrentIs("LPAREN"))
            {
                Advance();
                var expr = ParseOrExpression();
                Expect("RPAREN", "closing parenthesis");
                return expr;
            }

            if (CurrentIs("STRING"))
            {
                var t = Advance();
                if (legacyQuotedStrings)
                    return new ExprResult("text", t.Value, $"str(\"{t.Value}\")");
                if (SymbolExists(t.Value))
                    return FormatSymbolReference(t);
                throw new CompileError("SEMANTIC", "S036", t.Line, t.Column, $"Unknown symbol \"{t.Value}\".");
            }

            if (CurrentIs("IDENT"))
            {
                var t = Advance();
                return FormatVariableReference(t, _parsingCondition ? "S020" : "S010", name => _parsingCondition ? $"Unknown variable \"{name}\" in comparison." : $"Unknown variable \"{name}\".");
            }

            if (CurrentIs("INT"))
                return ParseIntLiteral();

            if (CurrentIs("DECIMAL"))
                return ParseNumericLiteral("double");

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
        bool IsExpressionEnd() => CurrentIs("NEWLINE") || CurrentIs("EOF") || CurrentIs("RPAREN") || IsKeyword("to") || IsKeyword("from") || IsKeyword("by") || IsKeyword("else") || IsKeyword("end");
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
