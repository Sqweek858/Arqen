using System.Globalization;
using System.Text;

static partial class Program
{
    sealed partial class Parser
    {
        // M18FG parser split: Core.

        const double NumericEpsilon = 0.0000000001;

        List<Token> _tokens;

        readonly Dictionary<string, VarInfo> _vars = new(StringComparer.Ordinal);

        readonly List<(string Name, string Type, string Value)> _varList = new();

        readonly List<string> _flow = new();

        readonly List<string> _prints = new();

        readonly List<RuntimeAction> _runtimeActions = new();

        readonly List<StyleProperty> _styles = new();

        readonly HashSet<string> _styleBlocks = new(StringComparer.Ordinal);

        readonly HashSet<string> _runtimeSymbols = new(StringComparer.Ordinal);

        readonly Dictionary<string, List<Token>> _functions = new(StringComparer.Ordinal);

        readonly HashSet<string> _callStack = new(StringComparer.Ordinal);

        readonly HashSet<string> _definedWindows = new(StringComparer.Ordinal);

        readonly HashSet<string> _shownWindows = new(StringComparer.Ordinal);

        readonly HashSet<string> _definedEvents = new(StringComparer.Ordinal);

        readonly List<StatementRule> _statementRules;

        uint _randomState = 0x6D2B79F5u;

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
                new StatementRule(() => IsKeyword("with") && PeekKeyword("style") && PeekKeyword("for", 2), ParseStyleStatement),
                new StatementRule(() => IsKeyword("let"), ParseLegacyLetStatement),
                new StatementRule(() => IsKeyword("define"), ParseCanonicalDefineStatement),
                new StatementRule(() => IsKeyword("rename"), ParseRenameStatement),
                new StatementRule(() => IsKeyword("print"), ParsePrintStatement),
                new StatementRule(() => IsKeyword("set") && PeekWord("random") && PeekWord("seed", 2), ParseRandomSeedStatement),
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

            return new AstModel(program, _varList, _title!, _titleExpr, _titleCommand, _message!, _messageExpr, _messageCommand, _exitCode, _finalCommand, _flow, _runtimeActions, _styles);
        }

        record CommandExpr(string Value, string Repr, string Command);

        record StatementRule(Func<bool> Matches, Action<bool, bool> Parse);

    }
}
