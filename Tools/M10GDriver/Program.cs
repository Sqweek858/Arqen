using System.Globalization;
using System.Text;


static partial class Program
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


}
