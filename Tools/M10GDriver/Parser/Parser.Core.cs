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

        readonly List<StylePresetProperty> _stylePresets = new();

        readonly List<StyleApplication> _styleApplies = new();

        readonly List<UiObject> _uiObjects = new();

        readonly List<UiProperty> _uiProperties = new();

        readonly List<UiLayoutProperty> _uiLayoutProperties = new();

        readonly List<UiParent> _uiParents = new();

        readonly List<UiDock> _uiDocks = new();

        readonly List<UiEvent> _uiEvents = new();

        readonly List<UiBinding> _uiBindings = new();

        readonly List<UiState> _uiStates = new();

        readonly List<UiResource> _uiResources = new();

        readonly List<UiResourceUse> _uiResourceUses = new();

        readonly List<Dx12Renderer> _dx12Renderers = new();

        readonly List<Dx12RendererParent> _dx12RendererParents = new();

        readonly List<Dx12RendererClearStyle> _dx12RendererClearStyles = new();

        readonly List<Dx12RendererClearReady> _dx12RendererClearReadies = new();

        readonly List<Dx12FrameCommand> _dx12FrameCommands = new();

        readonly List<Dx12Shader> _dx12Shaders = new();

        readonly List<Dx12Pipeline> _dx12Pipelines = new();

        readonly List<Dx12PipelineBind> _dx12PipelineBinds = new();

        readonly List<Dx12VertexBuffer> _dx12VertexBuffers = new();

        readonly List<Dx12Vertex> _dx12Vertices = new();

        readonly List<Dx12VertexBufferBind> _dx12VertexBufferBinds = new();

        readonly List<Dx12Draw> _dx12Draws = new();

        readonly List<Dx12Object> _dx12Objects = new();

        readonly List<Dx12ObjectBinding> _dx12ObjectBindings = new();

        readonly List<Dx12DrawObject> _dx12DrawObjects = new();

        readonly List<Dx12ObjectTransform> _dx12ObjectTransforms = new();

        readonly List<Dx12ObjectPrimitive> _dx12ObjectPrimitives = new();

        readonly List<Dx12Camera> _dx12Cameras = new();

        readonly List<Dx12CameraUse> _dx12CameraUses = new();

        readonly List<Dx12CameraProjection> _dx12CameraProjections = new();

        readonly List<Dx12CameraTransform> _dx12CameraTransforms = new();

        readonly List<Dx12KeyBinding> _dx12KeyBindings = new();

        readonly List<Dx12MouseCapture> _dx12MouseCaptures = new();

        readonly List<Dx12MouseMoveBinding> _dx12MouseMoveBindings = new();

        readonly List<Dx12MouseButtonBinding> _dx12MouseButtonBindings = new();

        readonly List<Dx12MouseWheelBinding> _dx12MouseWheelBindings = new();

        readonly List<Dx12ConstantBuffer> _dx12ConstantBuffers = new();

        readonly List<Dx12ConstantBufferBind> _dx12ConstantBufferBinds = new();

        readonly List<Dx12ColorSequence> _dx12ColorSequences = new();

        readonly List<Dx12ColorKey> _dx12ColorKeys = new();

        readonly List<Dx12AnimateColor> _dx12AnimateColors = new();

        readonly HashSet<string> _dx12RendererNames = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12RendererWindowByName = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12RendererClearStyleKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12FrameOpenRenderers = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12FrameClearedRenderers = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12FrameEndedRenderers = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12FramePresentedRenderers = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12ShaderNames = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12ShaderVertexByName = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12ShaderPixelByName = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12PipelineNames = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12PipelineRendererByName = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12PipelineShaderByName = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12PipelineBindKeys = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12PipelineByRenderer = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12VertexBufferNames = new(StringComparer.Ordinal);

        readonly Dictionary<string, int> _dx12VertexBufferCountByName = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12VertexBufferByRenderer = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12ConstantBufferNames = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12ConstantBufferTintByName = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12ConstantBufferByPipeline = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12ConstantBufferBindKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12ColorSequenceNames = new(StringComparer.Ordinal);

        readonly Dictionary<string, int> _dx12ColorSequenceCountByName = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12AnimateColorTargets = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12DrawnRenderers = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12ObjectNames = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12ObjectPrimitiveByName = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12ObjectRendererByName = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12ObjectPipelineByName = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12ObjectVertexBufferByName = new(StringComparer.Ordinal);

        readonly Dictionary<string, int> _dx12ObjectVertexCountByName = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12ObjectBindingKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12DrawnObjects = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12CameraNames = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12CameraByRenderer = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _dx12CameraRendererByName = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12CameraProjectionKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12ObjectTransformKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12CameraTransformKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12KeyBindingKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12MouseCaptureWindows = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12MouseMoveBindingKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12MouseButtonBindingKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _dx12MouseWheelBindingKeys = new(StringComparer.Ordinal);


        readonly Dictionary<string, string> _uiObjectTypes = new(StringComparer.Ordinal);

        readonly HashSet<string> _uiPropertyKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _uiOptionKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _uiLayoutPropertyKeys = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _uiParentByChild = new(StringComparer.Ordinal);

        readonly HashSet<string> _uiDockTargets = new(StringComparer.Ordinal);

        readonly HashSet<string> _uiEventKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _uiBindingKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _uiStateKeys = new(StringComparer.Ordinal);

        readonly Dictionary<string, string> _uiResourceTypes = new(StringComparer.Ordinal);

        readonly HashSet<string> _uiResourceUseKeys = new(StringComparer.Ordinal);

        readonly HashSet<string> _styleBlocks = new(StringComparer.Ordinal);

        readonly HashSet<string> _stylePresetNames = new(StringComparer.Ordinal);

        readonly HashSet<string> _styleApplications = new(StringComparer.Ordinal);

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
                new StatementRule(() => IsKeyword("define") && PeekKeyword("style"), ParseStylePresetStatement),
                new StatementRule(() => IsKeyword("use") && PeekKeyword("style"), ParseUseStyleStatement),
                new StatementRule(() => IsKeyword("with") && PeekKeyword("style") && PeekKeyword("for", 2), ParseStyleStatement),
                new StatementRule(() => IsKeyword("define") && LooksLikeUiObjectDefinition(), ParseUiObjectDefinitionStatement),
                new StatementRule(() => IsKeyword("set") && LooksLikeUiPropertySet(), ParseUiPropertySetStatement),
                new StatementRule(() => IsKeyword("add") && LooksLikeUiDropdownOption(), ParseUiDropdownOptionStatement),
                new StatementRule(() => CurrentWordIs("parent") && PeekWord("renderer"), ParseDx12RendererParentStatement),
                new StatementRule(() => CurrentWordIs("begin") && PeekWord("frame"), ParseDx12FrameBeginStatement),
                new StatementRule(() => CurrentWordIs("clear") && PeekWord("renderer"), ParseDx12RendererClearStatement),
                new StatementRule(() => CurrentWordIs("end") && PeekWord("frame"), ParseDx12FrameEndStatement),
                new StatementRule(() => CurrentWordIs("present") && PeekWord("frame"), ParseDx12FramePresentStatement),
                new StatementRule(() => IsKeyword("define") && PeekWord("shader"), ParseDx12ShaderDefinitionStatement),
                new StatementRule(() => IsKeyword("define") && PeekWord("dx12") && PeekWord("pipeline", 2), ParseDx12PipelineDefinitionStatement),
                new StatementRule(() => IsKeyword("define") && PeekWord("box"), ParseDx12BoxPrimitiveDefinitionStatement),
                new StatementRule(() => IsKeyword("define") && PeekWord("object"), ParseDx12ObjectDefinitionStatement),
                new StatementRule(() => IsKeyword("define") && PeekWord("camera"), ParseDx12CameraDefinitionStatement),
                new StatementRule(() => IsKeyword("use") && PeekWord("camera"), ParseDx12CameraUseStatement),
                new StatementRule(() => IsKeyword("use") && PeekWord("renderer"), ParseDx12ObjectRendererUseStatement),
                new StatementRule(() => IsKeyword("use") && PeekWord("pipeline"), ParseDx12PipelineUseStatement),
                new StatementRule(() => IsKeyword("define") && PeekWord("vertex") && PeekWord("buffer", 2), ParseDx12VertexBufferDefinitionStatement),
                new StatementRule(() => IsKeyword("use") && PeekWord("vertex") && PeekWord("buffer", 2), ParseDx12VertexBufferUseStatement),
                new StatementRule(() => IsKeyword("define") && PeekWord("constant") && PeekWord("buffer", 2), ParseDx12ConstantBufferDefinitionStatement),
                new StatementRule(() => IsKeyword("use") && PeekWord("constant") && PeekWord("buffer", 2), ParseDx12ConstantBufferUseStatement),
                new StatementRule(() => IsKeyword("define") && PeekWord("color") && PeekWord("sequence", 2), ParseDx12ColorSequenceDefinitionStatement),
                new StatementRule(() => CurrentWordIs("animate") && PeekWord("color"), ParseDx12AnimateColorStatement),
                new StatementRule(() => IsKeyword("set") && LooksLikeDx12TransformOrCameraStatement(), ParseDx12TransformOrCameraStatement),
                new StatementRule(() => CurrentWordIs("capture") && PeekWord("mouse"), ParseDx12MouseCaptureStatement),
                new StatementRule(() => CurrentWordIs("when") && PeekWord("mouse"), ParseDx12MouseInputStatement),
                new StatementRule(() => CurrentWordIs("when") && PeekWord("key") && !PeekWord("pressed", 2), ParseDx12KeyboardInputStatement),
                new StatementRule(() => CurrentWordIs("draw"), ParseDx12DrawStatement),
                new StatementRule(() => CurrentWordIs("parent"), ParseUiParentStatement),
                new StatementRule(() => CurrentWordIs("dock"), ParseUiDockStatement),
                new StatementRule(() => CurrentWordIs("link"), ParseUiBindingStatement),
                new StatementRule(() => IsKeyword("define") && LooksLikeUiResourceDefinition(), ParseUiResourceDefinitionStatement),
                new StatementRule(() => IsKeyword("set") && LooksLikeUiResourceUse(), ParseUiResourceUseStatement),
                new StatementRule(() => IsKeyword("set") && LooksLikeUiStateSet(), ParseUiStateStatement),
                new StatementRule(() => IsKeyword("with") && PeekWord("layout") && PeekKeyword("for", 2), ParseUiLayoutStatement),
                new StatementRule(() => IsKeyword("define") && PeekWord("dx12") && PeekWord("renderer", 2), ParseDx12RendererDefinitionStatement),
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

            FinalizeDx12RendererClearReadiness();
            FinalizeDx12ObjectBindings();

            SkipNewlines();
            ExpectKeyword("end");
            ExpectKeyword("program");
            var endName = ExpectName("end program name");
            if (endName != program)
                throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "end program name does not match program name.");
            ExpectLineOrEof();
            SkipNewlines();
            Expect("EOF", "end of file");

            return new AstModel(program, _varList, _title!, _titleExpr, _titleCommand, _message!, _messageExpr, _messageCommand, _exitCode, _finalCommand, _flow, _runtimeActions, _styles, _stylePresets, _styleApplies, _uiObjects, _uiProperties, _uiLayoutProperties, _uiParents, _uiDocks, _uiEvents, _uiBindings, _uiStates, _uiResources, _uiResourceUses, _dx12Renderers, _dx12RendererParents, _dx12RendererClearStyles, _dx12RendererClearReadies, _dx12FrameCommands, _dx12Shaders, _dx12Pipelines, _dx12PipelineBinds, _dx12VertexBuffers, _dx12Vertices, _dx12VertexBufferBinds, _dx12Draws, _dx12Objects, _dx12ObjectBindings, _dx12DrawObjects, _dx12ObjectTransforms, _dx12ObjectPrimitives, _dx12Cameras, _dx12CameraUses, _dx12CameraProjections, _dx12CameraTransforms, _dx12KeyBindings, _dx12MouseCaptures, _dx12MouseMoveBindings, _dx12MouseButtonBindings, _dx12MouseWheelBindings, _dx12ConstantBuffers, _dx12ConstantBufferBinds, _dx12ColorSequences, _dx12ColorKeys, _dx12AnimateColors);
        }

        record CommandExpr(string Value, string Repr, string Command);

        record StatementRule(Func<bool> Matches, Action<bool, bool> Parse);

    }
}
