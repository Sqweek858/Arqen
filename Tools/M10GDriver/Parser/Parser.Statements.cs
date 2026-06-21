using System.Globalization;
using System.Linq;
using System.Text;

static partial class Program
{
    sealed partial class Parser
    {
        // M18FG parser split: Statements.

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
            if (PeekWord("local"))
            {
                ParseLocalRuntimeDefinition(apply);
                return;
            }
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
                if (_dx12RendererNames.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S260", nameTok.Line, nameTok.Column, $"Window '{nameTok.Value}' conflicts with an existing DX12 renderer name.");
                if (_dx12ShaderNames.Contains(nameTok.Value) || _dx12PipelineNames.Contains(nameTok.Value) || _dx12VertexBufferNames.Contains(nameTok.Value) || _dx12ObjectNames.Contains(nameTok.Value))
                    throw new CompileError("SEMANTIC", "S280", nameTok.Line, nameTok.Column, $"Window '{nameTok.Value}' conflicts with an existing DX12 shader, pipeline, vertex buffer, or object name.");
                _definedWindows.Add(nameTok.Value);
                if (apply)
                    AddRuntimeAction(new RuntimeAction("window_create", "", "static", "", nameTok.Value));
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
                    AddRuntimeAction(new RuntimeAction("window_set_title", "", "static", titleTok.Value, nameTok.Value));
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
                    AddRuntimeAction(new RuntimeAction("window_set_resolution", "", "static", $"{w}x{h}", nameTok.Value));
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
                    AddRuntimeAction(new RuntimeAction("window_set_resizable", "", "static", boolTok.Value, nameTok.Value));
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
                    AddRuntimeAction(new RuntimeAction("window_close", "", "static", "", nameTok.Value));
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
                    AddRuntimeAction(new RuntimeAction("window_show", "", "static", "", nameTok.Value));
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
                    AddRuntimeAction(new RuntimeAction("window_run", "", "static", "", nameTok.Value));
                    _finalCommand = "exit";
                }
            }
        }

        void ParseRandomSeedStatement(bool apply, bool inIf)
        {
            ExpectKeyword("set");
            ExpectWord("random", "P180", "Expected random after set.");
            ExpectWord("seed", "P181", "Expected seed after set random.");
            ExpectKeyword("to");
            var seed = ParseAddExpression(legacyQuotedStrings: false);
            ExpectLine();

            if (!apply)
                return;

            if (!IsNumeric(seed.Type))
                throw new CompileError("SEMANTIC", "S180", Current.Line, Current.Column, "random seed must be numeric.");

            var value = ToNumber(seed);
            if (double.IsNaN(value) || double.IsInfinity(value) || Math.Abs(value - Math.Round(value)) > NumericEpsilon || value < 0 || value > uint.MaxValue)
                throw new CompileError("SEMANTIC", "S180", Current.Line, Current.Column, "random seed must be a non-negative integer within uint range.");

            _randomState = (uint)Math.Round(value);
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
                {
                    var slotName = RuntimeSlotName(slotTok);
                    AddRuntimeAction(new RuntimeAction("print_runtime_slot", "", "slot", slotName, slotName));
                }
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
                throw new CompileError("PARSE", "P054", Current.Line, Current.Column, "Nested compile-time if statements are not supported in M13. Use runtime if for nested runtime branches.");
            ParseCompileTimeIf(apply);
        }

        void ParseRuntimeIfStatement(bool apply, bool inIf)
        {
            ExpectWord("runtime", "P120", "Expected runtime if.");
            ExpectKeyword("if");
            var condition = ParseRuntimeIfCondition();
            ExpectLine();

            if (apply)
                AddRuntimeAction(new RuntimeAction(condition.ActionOp, condition.Op, condition.RightKind, condition.Right, condition.Left));

            SkipNewlines();
            while (!CurrentIs("EOF") && !IsKeyword("else") && !IsEndIf())
            {
                ParseStatement(apply, inIf: false);
                SkipNewlines();
            }

            if (IsKeyword("else"))
            {
                ExpectKeyword("else");
                ExpectLine();
                if (apply)
                    AddRuntimeAction(new RuntimeAction("runtime_else", "", "static", "", ""));

                SkipNewlines();
                while (!CurrentIs("EOF") && !IsEndIf())
                {
                    ParseStatement(apply, inIf: false);
                    SkipNewlines();
                }
            }

            if (!IsEndIf())
                throw new CompileError("PARSE", "P057", Current.Line, Current.Column, "Expected end if for runtime if.");
            ExpectKeyword("end");
            ExpectKeyword("if");
            ExpectLine();

            if (apply)
                AddRuntimeAction(new RuntimeAction("runtime_if_end", "", "static", "", ""));
        }

        void ParseRuntimeSwitchStatement(bool apply, bool inIf)
        {
            ExpectWord("runtime", "P177", "Expected runtime switch.");
            ExpectWord("switch", "P177", "Expected switch after runtime.");

            if (CurrentWordIs("enum"))
            {
                ParseRuntimeSwitchEnumStatement(apply);
                return;
            }

            if (CurrentWordIs("int"))
            {
                ParseRuntimeSwitchIntStatement(apply);
                return;
            }

            throw new CompileError("PARSE", "P177", Current.Line, Current.Column, "runtime switch supports enum and int in M57/M58.");
        }

        static string RuntimeSwitchMatchSlotName(int switchId)
            => "__switch_match_" + switchId.ToString(CultureInfo.InvariantCulture);

        void ParseRuntimeSwitchBody(bool apply)
        {
            SkipNewlines();
            while (!CurrentIs("EOF") && !IsRuntimeSwitchBodyBoundary())
            {
                ParseStatement(apply, inIf: false);
                SkipNewlines();
            }
        }

        void ParseRuntimeSwitchEnd(string context)
        {
            if (!IsEndSwitch())
                throw new CompileError("PARSE", "P180", Current.Line, Current.Column, $"Expected end switch for {context}.");
            ExpectWord("end", "P180", "Expected end switch.");
            ExpectWord("switch", "P180", "Expected switch after end.");
            ExpectLine();
        }

        void EmitRuntimeSwitchCaseStart(string matchedSlot, string targetSlot, string valueKind, string value)
        {
            AddRuntimeAction(new RuntimeAction("runtime_if_bool", "eq", "static", "false", matchedSlot));
            AddRuntimeAction(new RuntimeAction("runtime_if_int", "eq", valueKind, value, targetSlot));
        }

        void EmitRuntimeSwitchCaseEnd(string matchedSlot)
        {
            AddRuntimeAction(new RuntimeAction("runtime_bool_set", "", "static", "true", matchedSlot));
            AddRuntimeAction(new RuntimeAction("runtime_if_end", "", "static", "", ""));
            AddRuntimeAction(new RuntimeAction("runtime_if_end", "", "static", "", ""));
        }

        void EmitRuntimeSwitchDefaultStart(string matchedSlot)
        {
            AddRuntimeAction(new RuntimeAction("runtime_if_bool", "eq", "static", "false", matchedSlot));
        }

        void EmitRuntimeSwitchDefaultEnd()
        {
            AddRuntimeAction(new RuntimeAction("runtime_if_end", "", "static", "", ""));
        }

        void ParseRuntimeSwitchEnumStatement(bool apply)
        {
            ExpectWord("enum", "P177", "Expected enum after runtime switch.");
            var enumTok = Expect("STRING", "runtime enum switch name");
            var instance = RequireRuntimeEnum(enumTok, "runtime switch enum");
            if (!_runtimeEnumTypes.TryGetValue(instance.TypeName, out var enumType))
                throw new CompileError("SEMANTIC", "S217", enumTok.Line, enumTok.Column, $"Runtime enum type \"{instance.TypeName}\" is not defined.");
            ExpectLine();

            var switchId = ++_runtimeSwitchCounter;
            var matchedSlot = RuntimeSwitchMatchSlotName(switchId);
            var enumSlot = RuntimeEnumStorageName(instance);
            var seenCases = new HashSet<string>(StringComparer.Ordinal);
            var sawCase = false;
            var sawDefault = false;

            if (apply)
                AddRuntimeAction(new RuntimeAction("runtime_bool_set", "", "static", "false", matchedSlot));

            SkipNewlines();
            while (!CurrentIs("EOF") && !IsEndSwitch())
            {
                if (CurrentWordIs("case"))
                {
                    if (sawDefault)
                        throw new CompileError("SEMANTIC", "S221", Current.Line, Current.Column, "runtime switch enum case cannot appear after default.");
                    ExpectWord("case", "P178", "Expected case in runtime switch enum.");
                    var valueTok = Expect("STRING", "runtime switch enum case value");
                    var valueIndex = RuntimeEnumValueIndex(enumType, valueTok, "runtime switch enum case");
                    if (!seenCases.Add(valueTok.Value))
                        throw new CompileError("SEMANTIC", "S218", valueTok.Line, valueTok.Column, $"Duplicate enum switch case \"{valueTok.Value}\" for enum \"{enumType.Name}\".");
                    ExpectLine();
                    sawCase = true;

                    if (apply)
                        EmitRuntimeSwitchCaseStart(matchedSlot, enumSlot, "static", valueIndex.ToString(CultureInfo.InvariantCulture));
                    ParseRuntimeSwitchBody(apply);
                    if (apply)
                        EmitRuntimeSwitchCaseEnd(matchedSlot);
                    continue;
                }

                if (CurrentWordIs("default"))
                {
                    if (sawDefault)
                        throw new CompileError("SEMANTIC", "S220", Current.Line, Current.Column, "Duplicate default in runtime switch enum.");
                    ExpectWord("default", "P179", "Expected default in runtime switch enum.");
                    ExpectLine();
                    sawDefault = true;

                    if (apply)
                        EmitRuntimeSwitchDefaultStart(matchedSlot);
                    ParseRuntimeSwitchBody(apply);
                    if (apply)
                        EmitRuntimeSwitchDefaultEnd();
                    continue;
                }

                throw new CompileError("PARSE", "P180", Current.Line, Current.Column, "Expected case, default, or end switch in runtime switch enum.");
            }

            if (!sawCase && !sawDefault)
                throw new CompileError("SEMANTIC", "S219", enumTok.Line, enumTok.Column, "runtime switch enum requires at least one case or default.");
            ParseRuntimeSwitchEnd("runtime switch enum");
        }

        int ParseRuntimeSwitchIntCaseValue(string context)
        {
            var sign = "";
            if (CurrentIs("MINUS"))
            {
                sign = "-";
                Advance();
            }
            var valueTok = Expect("INT", context);
            var raw = sign + valueTok.Value;
            if (!int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value))
                throw new CompileError("SEMANTIC", "S222", valueTok.Line, valueTok.Column, $"runtime switch int case must fit i32: {raw}.");
            return value;
        }

        void ParseRuntimeSwitchIntStatement(bool apply)
        {
            ExpectWord("int", "P177", "Expected int after runtime switch.");
            var intTok = Expect("STRING", "runtime int switch name");
            RequireRuntimeIntSymbol(intTok, "S132", "runtime switch int target");
            ExpectLine();

            var switchId = ++_runtimeSwitchCounter;
            var matchedSlot = RuntimeSwitchMatchSlotName(switchId);
            var intSlot = RuntimeSlotName(intTok);
            var seenCases = new HashSet<int>();
            var sawCase = false;
            var sawDefault = false;

            if (apply)
                AddRuntimeAction(new RuntimeAction("runtime_bool_set", "", "static", "false", matchedSlot));

            SkipNewlines();
            while (!CurrentIs("EOF") && !IsEndSwitch())
            {
                if (CurrentWordIs("case"))
                {
                    if (sawDefault)
                        throw new CompileError("SEMANTIC", "S221", Current.Line, Current.Column, "runtime switch int case cannot appear after default.");
                    ExpectWord("case", "P178", "Expected case in runtime switch int.");
                    var value = ParseRuntimeSwitchIntCaseValue("runtime switch int case value");
                    if (!seenCases.Add(value))
                        throw new CompileError("SEMANTIC", "S223", Current.Line, Current.Column, $"Duplicate runtime switch int case {value.ToString(CultureInfo.InvariantCulture)}.");
                    ExpectLine();
                    sawCase = true;

                    if (apply)
                        EmitRuntimeSwitchCaseStart(matchedSlot, intSlot, "static", value.ToString(CultureInfo.InvariantCulture));
                    ParseRuntimeSwitchBody(apply);
                    if (apply)
                        EmitRuntimeSwitchCaseEnd(matchedSlot);
                    continue;
                }

                if (CurrentWordIs("default"))
                {
                    if (sawDefault)
                        throw new CompileError("SEMANTIC", "S220", Current.Line, Current.Column, "Duplicate default in runtime switch int.");
                    ExpectWord("default", "P179", "Expected default in runtime switch int.");
                    ExpectLine();
                    sawDefault = true;

                    if (apply)
                        EmitRuntimeSwitchDefaultStart(matchedSlot);
                    ParseRuntimeSwitchBody(apply);
                    if (apply)
                        EmitRuntimeSwitchDefaultEnd();
                    continue;
                }

                throw new CompileError("PARSE", "P180", Current.Line, Current.Column, "Expected case, default, or end switch in runtime switch int.");
            }

            if (!sawCase && !sawDefault)
                throw new CompileError("SEMANTIC", "S219", intTok.Line, intTok.Column, "runtime switch int requires at least one case or default.");
            ParseRuntimeSwitchEnd("runtime switch int");
        }

        void ParseRuntimeWhileStatement(bool apply, bool inIf)
        {
            ExpectWord("runtime", "P122", "Expected runtime while.");
            ExpectKeyword("while");
            var condition = ParseRuntimeIntCondition("while");
            ExpectLine();

            if (apply)
                AddRuntimeAction(new RuntimeAction("runtime_while_int", condition.Op, condition.RightKind, condition.Right, condition.Left));

            _runtimeWhileParseDepth++;
            try
            {
                SkipNewlines();
                while (!CurrentIs("EOF") && !IsEndWhile())
                {
                    ParseStatement(apply, inIf: false);
                    SkipNewlines();
                }
            }
            finally
            {
                _runtimeWhileParseDepth--;
            }

            if (!IsEndWhile())
                throw new CompileError("PARSE", "P080", Current.Line, Current.Column, "Expected end while for runtime while.");
            ExpectKeyword("end");
            ExpectKeyword("while");
            ExpectLine();

            if (apply)
                AddRuntimeAction(new RuntimeAction("runtime_while_end", "", "static", "", ""));
        }

        void ParseRuntimeSetStatement(bool apply, bool inIf)
        {
            ExpectKeyword("set");
            ExpectWord("runtime", "P123", "Expected runtime set.");

            if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                throw new CompileError("PARSE", "P123", Current.Line, Current.Column, "Expected runtime set type: int, bool, or string.");

            var declaredType = Advance().Value;
            var targetTok = Expect("STRING", $"runtime {declaredType} symbol name");
            if (!IsKeyword("to"))
                throw new CompileError("PARSE", "P075", Current.Line, Current.Column, $"Expected keyword \"to\" after runtime {declaredType} target.");
            ExpectKeyword("to");

            if (IsKeyword("call"))
            {
                var call = ParseFunctionCallExpression();
                ExpectLine();

                if (!apply)
                    return;

                if (declaredType == "int")
                    RequireRuntimeIntSymbol(targetTok, "S133", "set runtime int target");
                else if (declaredType == "bool")
                    RequireRuntimeBoolSymbol(targetTok, "S143", "set runtime bool target");
                else
                    RequireRuntimeStringSymbol(targetTok, "S144", "set runtime string target");

                if (!_runtimeFunctionMap.TryGetValue(call.Name, out var fn))
                    throw new CompileError("SEMANTIC", "S050", call.NameToken.Line, call.NameToken.Column, $"Unknown function \"{call.Name}\".");
                if (fn.ReturnType == "void")
                    throw new CompileError("SEMANTIC", "S162", call.NameToken.Line, call.NameToken.Column, $"Function \"{call.Name}\" returns void and cannot be assigned to a runtime {declaredType} slot.");
                if (fn.ReturnType != declaredType)
                    throw new CompileError("SEMANTIC", "S163", call.NameToken.Line, call.NameToken.Column, $"Function \"{call.Name}\" returns {fn.ReturnType}, not {declaredType}.");

                AddFunctionArgumentSetupActions(fn, call.Args, call.NameToken);
                AddRuntimeAction(new RuntimeAction("function_call_assign", declaredType, "static", call.Name, RuntimeSlotName(targetTok)));
                AddFunctionArgumentCopyBackActions(fn, call.Args, call.NameToken);
                return;
            }

            if (CurrentWordIs("runtime") && PeekWord("record") && PeekWord("array", 2))
            {
                var read = ParseRuntimeRecordArrayFieldReadExpression(declaredType, $"set runtime {declaredType} from record array field");
                ExpectLine();

                if (!apply)
                    return;

                if (declaredType == "int")
                    RequireRuntimeIntSymbol(targetTok, "S133", "set runtime int target");
                else if (declaredType == "bool")
                    RequireRuntimeBoolSymbol(targetTok, "S143", "set runtime bool target");
                else
                    RequireRuntimeStringSymbol(targetTok, "S144", "set runtime string target");

                AddRuntimeRecordArrayBoundsCheckedDispatch(read.Array, read.Index, i =>
                    AddRuntimeAction(new RuntimeAction($"runtime_{declaredType}_set", "", "slot", RuntimeRecordArrayFieldSlotName(read.Array, i, read.Field.Name), RuntimeSlotName(targetTok))));
                return;
            }

            if (CurrentWordIs("runtime") && PeekWord("record") && PeekString(2) && PeekWord("field", 3))
            {
                var read = ParseRuntimeRecordFieldReadExpression(declaredType, $"set runtime {declaredType} from record field");
                ExpectLine();

                if (!apply)
                    return;

                if (declaredType == "int")
                    RequireRuntimeIntSymbol(targetTok, "S133", "set runtime int target");
                else if (declaredType == "bool")
                    RequireRuntimeBoolSymbol(targetTok, "S143", "set runtime bool target");
                else
                    RequireRuntimeStringSymbol(targetTok, "S144", "set runtime string target");

                AddRuntimeAction(new RuntimeAction($"runtime_{declaredType}_set", "", "slot", read.Slot, RuntimeSlotName(targetTok)));
                return;
            }

            if (CurrentWordIs("runtime") && PeekKeyword(declaredType) && PeekWord("array", 2))
            {
                var read = ParseRuntimeArrayReadExpression(declaredType, $"set runtime {declaredType} from array");
                ExpectLine();

                if (!apply)
                    return;

                if (declaredType == "int")
                    RequireRuntimeIntSymbol(targetTok, "S133", "set runtime int target");
                else if (declaredType == "bool")
                    RequireRuntimeBoolSymbol(targetTok, "S143", "set runtime bool target");
                else
                    RequireRuntimeStringSymbol(targetTok, "S144", "set runtime string target");

                AddRuntimeArrayGetActions(read.Array, read.Index, RuntimeSlotName(targetTok));
                return;
            }

            if (declaredType == "int" && CurrentWordIs("length"))
            {
                var array = ParseRuntimeArrayLengthExpression("set runtime int from array length");
                ExpectLine();

                if (!apply)
                    return;

                RequireRuntimeIntSymbol(targetTok, "S133", "set runtime int target");
                AddRuntimeAction(new RuntimeAction("runtime_int_set", "", "static", array.Size.ToString(CultureInfo.InvariantCulture), RuntimeSlotName(targetTok)));
                return;
            }

            var boolNot = false;
            if (declaredType == "bool" && IsKeyword("not"))
            {
                ExpectKeyword("not");
                boolNot = true;
            }

            var actionOp = declaredType == "bool" && boolNot ? "runtime_bool_not_set" : $"runtime_{declaredType}_set";
            var actionPath = "";
            var value = (Kind: "", Value: "");

            if (declaredType == "int" && CurrentWordIs("parse"))
            {
                ExpectWord("parse", "P129", "Expected parse int expression.");
                ExpectKeyword("int");
                ExpectKeyword("from");
                value = ParseRuntimeStringOperand("parse int source");
                actionOp = "runtime_int_parse";
            }
            else if (declaredType == "string" && CurrentWordIs("substring"))
            {
                ExpectWord("substring", "P130", "Expected substring expression.");
                var source = ParseRuntimeStringOperand("substring source");
                ExpectKeyword("from");
                var startTok = Expect("INT", "substring start index");
                ExpectWord("length", "P130", "Expected length after substring start index.");
                var lengthTok = Expect("INT", "substring length");
                actionPath = EncodeRuntimeOperand(source);
                value = ("range", startTok.Value + ":" + lengthTok.Value);
                actionOp = "runtime_string_substring";
            }
            else
            {
                value = declaredType switch
                {
                    "int" => ParseRuntimeIntOperand("set runtime int"),
                    "bool" => ParseRuntimeBoolOperand(boolNot ? "set runtime bool not" : "set runtime bool"),
                    "string" => ParseRuntimeStringOperand("set runtime string"),
                    _ => throw new CompileError("PARSE", "P123", Current.Line, Current.Column, "Unsupported runtime set type.")
                };

                if (declaredType == "string" && CurrentIs("PLUS"))
                {
                    Expect("PLUS", "+");
                    var right = ParseRuntimeStringOperand("string concat right operand");
                    actionPath = EncodeRuntimeOperand(value);
                    value = right;
                    actionOp = "runtime_string_concat";
                }
            }

            ExpectLine();

            if (!apply)
                return;

            if (declaredType == "int")
                RequireRuntimeIntSymbol(targetTok, "S133", "set runtime int target");
            else if (declaredType == "bool")
                RequireRuntimeBoolSymbol(targetTok, "S143", "set runtime bool target");
            else
                RequireRuntimeStringSymbol(targetTok, "S144", "set runtime string target");

            AddRuntimeAction(new RuntimeAction(actionOp, actionPath, value.Kind, value.Value, RuntimeSlotName(targetTok)));
        }

        void ParseRuntimeToggleBoolStatement(bool apply, bool inIf)
        {
            ExpectWord("toggle", "P127", "Expected toggle runtime bool.");
            ExpectWord("runtime", "P127", "Expected runtime after toggle.");
            ExpectKeyword("bool");
            var targetTok = Expect("STRING", "runtime bool symbol name");
            ExpectLine();
            RequireRuntimeBoolSymbol(targetTok, "S147", "toggle runtime bool target");
            if (apply)
                AddRuntimeAction(new RuntimeAction("runtime_bool_toggle", "", "static", "", RuntimeSlotName(targetTok)));
        }

        (string Left, string ActionOp, string Op, string RightKind, string Right) ParseRuntimeIfCondition()
        {
            if (CurrentWordIs("enum"))
                return ParseRuntimeEnumIfCondition();

            var leftTok = Expect("STRING", "runtime if symbol name");
            var info = ResolveSymbol(leftTok, "S131", name => $"Unknown runtime symbol \"{name}\".");
            if (!info.IsRuntime)
                throw new CompileError("SEMANTIC", "S132", leftTok.Line, leftTok.Column, $"runtime if left operand \"{leftTok.Value}\" must be a runtime slot.");

            if (info.Type == "int")
            {
                var parsed = ParseRuntimeIntComparisonTail("if");
                return (RuntimeSlotName(leftTok), "runtime_if_int", parsed.Op, parsed.RightKind, parsed.Right);
            }

            if (info.Type == "bool")
            {
                var parsed = ParseRuntimeBoolComparisonTail("if");
                return (RuntimeSlotName(leftTok), "runtime_if_bool", parsed.Op, parsed.RightKind, parsed.Right);
            }

            if (info.Type == "text")
            {
                var parsed = ParseRuntimeStringComparisonTail("if");
                return (RuntimeSlotName(leftTok), "runtime_if_string", parsed.Op, parsed.RightKind, parsed.Right);
            }

            throw new CompileError("SEMANTIC", "S142", leftTok.Line, leftTok.Column, $"runtime if does not support symbol \"{leftTok.Value}\" of type {info.Type} as a runtime condition.");
        }

        (string Left, string Op, string RightKind, string Right) ParseRuntimeIntCondition(string keyword)
        {
            var leftTok = Expect("STRING", "runtime int symbol name");
            RequireRuntimeIntSymbol(leftTok, "S132", $"runtime {keyword} left operand");
            var parsed = ParseRuntimeIntComparisonTail(keyword);
            return (RuntimeSlotName(leftTok), parsed.Op, parsed.RightKind, parsed.Right);
        }

        (string Op, string RightKind, string Right) ParseRuntimeIntComparisonTail(string keyword)
        {
            var op = "eq";
            if (IsKeyword("is"))
            {
                ExpectKeyword("is");
                if (IsKeyword("not"))
                {
                    ExpectKeyword("not");
                    op = "ne";
                }
                else if (CurrentWordIs("less"))
                {
                    ExpectWord("less", "P121", "Expected runtime comparison operator.");
                    ExpectWord("than", "P121", "Expected keyword \"than\" after less.");
                    op = "lt";
                }
                else if (CurrentWordIs("greater"))
                {
                    ExpectWord("greater", "P121", "Expected runtime comparison operator.");
                    ExpectWord("than", "P121", "Expected keyword \"than\" after greater.");
                    op = "gt";
                }
            }
            else if (CurrentWordIs("equals"))
            {
                ExpectWord("equals", "P121", "Expected comparison operator.");
                op = "eq";
            }
            else if (CurrentWordIs("less"))
            {
                ExpectWord("less", "P121", "Expected comparison operator.");
                ExpectWord("than", "P121", "Expected keyword \"than\" after less.");
                op = "lt";
            }
            else if (CurrentWordIs("greater"))
            {
                ExpectWord("greater", "P121", "Expected comparison operator.");
                ExpectWord("than", "P121", "Expected keyword \"than\" after greater.");
                op = "gt";
            }
            else
            {
                throw new CompileError("PARSE", "P121", Current.Line, Current.Column, "Runtime int comparisons support \"is\", \"is not\", \"equals\", \"less than\", and \"greater than\".");
            }

            var right = ParseRuntimeIntOperand($"runtime {keyword} integer literal or runtime int slot");
            return (op, right.Kind, right.Value);
        }

        (string Op, string RightKind, string Right) ParseRuntimeBoolComparisonTail(string keyword)
        {
            var op = "eq";
            if (IsKeyword("is"))
            {
                ExpectKeyword("is");
                if (IsKeyword("not"))
                {
                    ExpectKeyword("not");
                    op = "ne";
                }
            }
            else if (CurrentWordIs("equals"))
            {
                ExpectWord("equals", "P126", "Expected bool comparison operator.");
                op = "eq";
            }
            else
            {
                throw new CompileError("PARSE", "P126", Current.Line, Current.Column, "Runtime bool comparisons support \"is true\", \"is false\", \"is not true\", and \"equals false\".");
            }

            var right = ParseRuntimeBoolOperand($"runtime {keyword} bool literal or runtime bool slot");
            return (op, right.Kind, right.Value);
        }

        (string Op, string RightKind, string Right) ParseRuntimeStringComparisonTail(string keyword)
        {
            var op = "eq";
            if (CurrentWordIs("contains"))
            {
                ExpectWord("contains", "P128", "Expected runtime string comparison operator.");
                op = "contains";
            }
            else if (IsKeyword("is"))
            {
                ExpectKeyword("is");
                if (IsKeyword("not"))
                {
                    ExpectKeyword("not");
                    op = "ne";
                }
            }
            else if (CurrentWordIs("equals"))
            {
                ExpectWord("equals", "P128", "Expected runtime string comparison operator.");
                op = "eq";
            }
            else
            {
                throw new CompileError("PARSE", "P128", Current.Line, Current.Column, "Runtime string comparisons support equals, is, is not, and contains with runtime string operands.");
            }

            if (CurrentWordIs("less") || CurrentWordIs("greater"))
                throw new CompileError("SEMANTIC", "S148", Current.Line, Current.Column, "Runtime string comparisons support equality/contains only in M37.");

            var right = ParseRuntimeStringOperand($"runtime {keyword} string literal or runtime string slot");

            if (CurrentWordIs("ignoring"))
            {
                ExpectWord("ignoring", "P128", "Expected ignoring case suffix.");
                ExpectWord("case", "P128", "Expected case after ignoring.");
                if (op == "contains")
                    throw new CompileError("SEMANTIC", "S149", Current.Line, Current.Column, "contains ignoring case is reserved; M37 supports ignoring case for equality only.");
                op = op == "ne" ? "ne_ci" : "eq_ci";
            }

            return (op, right.Kind, right.Value);
        }

        (string Kind, string Value) ParseRuntimeIntOperand(string context)
        {
            if (CurrentIs("STRING"))
            {
                var symbolTok = Advance();
                RequireRuntimeIntSymbol(symbolTok, "S137", context);
                return ("slot", RuntimeSlotName(symbolTok));
            }

            var sign = "";
            if (CurrentIs("MINUS"))
            {
                sign = "-";
                Advance();
            }
            var valueTok = Expect("INT", context);
            return ("static", sign + valueTok.Value);
        }

        (string Kind, string Value) ParseRuntimeBoolOperand(string context)
        {
            if (CurrentIs("STRING"))
            {
                var symbolTok = Advance();
                RequireRuntimeBoolSymbol(symbolTok, "S145", context);
                return ("slot", RuntimeSlotName(symbolTok));
            }

            if (!CurrentIs("BOOL"))
                throw new CompileError("SEMANTIC", "S140", Current.Line, Current.Column, $"{context} requires true/false or a runtime bool slot.");
            return ("static", Advance().Value);
        }

        (string Kind, string Value) ParseRuntimeStringOperand(string context)
        {
            if (IsKeyword("string"))
                return ParseRuntimeStringStaticLiteral(context);

            if (CurrentIs("STRING"))
            {
                var symbolTok = Advance();
                RequireRuntimeStringSymbol(symbolTok, "S146", context);
                return ("slot", RuntimeSlotName(symbolTok));
            }

            throw new CompileError("SEMANTIC", "S141", Current.Line, Current.Column, $"{context} requires string \"...\" or a runtime string slot.");
        }

        (string Kind, string Value) ParseRuntimeTypedOperand(string declaredType, string context)
        {
            if (IsRuntimeEnumParamType(declaredType))
            {
                var enumTypeName = RuntimeEnumTypeNameFromParam(declaredType);
                if (!_runtimeEnumTypes.TryGetValue(enumTypeName, out var enumType))
                    throw new CompileError("SEMANTIC", "S217", Current.Line, Current.Column, $"Runtime enum type \"{enumTypeName}\" is not defined.");
                return ParseRuntimeEnumOperand(enumType, context);
            }

            if (CurrentWordIs("runtime"))
            {
                ExpectWord("runtime", "P164", $"Expected runtime typed operand for {context}.");
                if (!CurrentIs("KEYWORD") || Current.Value != declaredType)
                    throw new CompileError("SEMANTIC", "S202", Current.Line, Current.Column, $"{context} expects runtime {declaredType} slot source.");
                Advance();
            }

            return declaredType switch
            {
                "int" => ParseRuntimeIntOperand(context),
                "bool" => ParseRuntimeBoolOperand(context),
                "string" => ParseRuntimeStringOperand(context),
                _ => throw new CompileError("PARSE", "P164", Current.Line, Current.Column, "Unsupported runtime typed operand type.")
            };
        }

        static string EncodeRuntimeOperand((string Kind, string Value) operand)
            => operand.Kind + ":" + operand.Value;

        string RuntimeSlotName(Token token)
            => _runtimeParamAliases.TryGetValue(token.Value, out var slot) ? slot : token.Value;

        static string RuntimeArrayStorageName(RuntimeArrayInfo array)
            => string.IsNullOrWhiteSpace(array.Slot) ? array.Name : array.Slot;

        static string RuntimeArrayElementSlotName(string arrayName, string runtimeType, int index)
        {
            var sanitized = SanitizeInternalName(arrayName);
            var suffix = index.ToString(CultureInfo.InvariantCulture);
            return runtimeType == "int"
                ? "__arr_" + sanitized + "_" + suffix
                : "__arr_" + sanitized + "_" + runtimeType + "_" + suffix;
        }

        static string RuntimeArrayElementSlotName(RuntimeArrayInfo array, int index)
            => RuntimeArrayElementSlotName(RuntimeArrayStorageName(array), array.Type, index);

        static string RuntimeArrayBoundsSlotName(RuntimeArrayInfo array, int id)
            => "__arr_" + SanitizeInternalName(RuntimeArrayStorageName(array)) + "_bounds_ok_" + id.ToString(CultureInfo.InvariantCulture);

        static string RuntimeArrayIndexTempSlotName(RuntimeArrayInfo array, int id)
            => "__arr_" + SanitizeInternalName(RuntimeArrayStorageName(array)) + "_index_" + id.ToString(CultureInfo.InvariantCulture);

        static string RuntimeLocalArraySlotName(string functionName, string arrayName)
            => "__fn_" + SanitizeInternalName(functionName) + "_local_arr_" + SanitizeInternalName(arrayName);

        static string RuntimeParamArraySlotName(string functionName, string arrayName)
            => "__fn_" + SanitizeInternalName(functionName) + "_param_arr_" + SanitizeInternalName(arrayName);

        static string RuntimeLocalRecordSlotName(string functionName, string recordName)
            => "__fn_" + SanitizeInternalName(functionName) + "_local_rec_" + SanitizeInternalName(recordName);

        static string RuntimeParamRecordSlotName(string functionName, string recordName)
            => "__fn_" + SanitizeInternalName(functionName) + "_param_rec_" + SanitizeInternalName(recordName);

        static bool IsRuntimeArrayType(string type)
            => type is "int_array" or "bool_array" or "string_array";

        static bool IsRuntimeRecordParamType(string type)
            => type.StartsWith("record:", StringComparison.Ordinal);

        static bool IsRuntimeEnumParamType(string type)
            => type.StartsWith("enum:", StringComparison.Ordinal);

        static bool IsRuntimeEnumArrayParamType(string type)
            => type.StartsWith("enum_array:", StringComparison.Ordinal);

        static string RuntimeRecordTypeNameFromParam(string type)
            => IsRuntimeRecordParamType(type) ? type["record:".Length..] : type;

        static string RuntimeEnumTypeNameFromParam(string type)
            => IsRuntimeEnumParamType(type) ? type["enum:".Length..] : type;

        static string RuntimeEnumArrayTypeNameFromParam(string type)
            => IsRuntimeEnumArrayParamType(type) ? type["enum_array:".Length..] : type;

        static string RuntimeStorageActionType(string runtimeType)
            => IsRuntimeEnumParamType(runtimeType) ? "int" : runtimeType;

        static string RuntimeArrayElementType(string arrayType)
            => arrayType.EndsWith("_array", StringComparison.Ordinal) ? arrayType[..^6] : arrayType;

        RuntimeArrayInfo RequireRuntimeArray(Token arrayTok, string expectedType, string code, string context)
        {
            if (_runtimeArrays.TryGetValue(arrayTok.Value, out var info))
            {
                if (info.Type != expectedType)
                    throw new CompileError("SEMANTIC", "S190", arrayTok.Line, arrayTok.Column, $"{context} expects a runtime {expectedType} array, but array \"{arrayTok.Value}\" is runtime {info.Type} array.");
                return info;
            }
            throw new CompileError("SEMANTIC", code, arrayTok.Line, arrayTok.Column, $"{context} references unknown runtime {expectedType} array \"{arrayTok.Value}\".");
        }

        RuntimeArrayIndex ParseRuntimeArrayIndex(RuntimeArrayInfo array, string context)
        {
            ExpectWord("at", "P150", $"Expected at before {context} array index.");

            if (CurrentWordIs("runtime"))
            {
                ExpectWord("runtime", "P151", "Expected runtime int array index.");
                ExpectKeyword("int");
                var operand = ParseRuntimeIntOperand(context + " runtime index");
                if (operand.Kind != "slot")
                    throw new CompileError("SEMANTIC", "S181", Current.Line, Current.Column, "Dynamic runtime array index must reference a runtime int slot.");
                return new RuntimeArrayIndex("slot", operand.Value, -1);
            }

            var sign = "";
            if (CurrentIs("MINUS"))
            {
                sign = "-";
                Advance();
            }
            var idxTok = Expect("INT", context + " static index");
            var raw = sign + idxTok.Value;
            if (!int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var index))
                throw new CompileError("SEMANTIC", "S182", idxTok.Line, idxTok.Column, $"Runtime array index must fit i32: {raw}.");
            if (index < 0 || index >= array.Size)
                throw new CompileError("SEMANTIC", "S183", idxTok.Line, idxTok.Column, $"Runtime array index {index} is outside array \"{array.Name}\" bounds 0..{array.Size - 1}.");
            return new RuntimeArrayIndex("static", index.ToString(CultureInfo.InvariantCulture), index);
        }

        void AddRuntimeArrayBoundsCheckedDispatch(RuntimeArrayInfo array, RuntimeArrayIndex index, Action<int> emitForIndex)
        {
            if (index.Kind == "static")
            {
                emitForIndex(index.StaticIndex);
                return;
            }

            var dispatchId = ++_runtimeArrayDispatchCounter;
            var okSlot = RuntimeArrayBoundsSlotName(array, dispatchId);
            var indexSlot = RuntimeArrayIndexTempSlotName(array, dispatchId);

            AddRuntimeAction(new RuntimeAction("runtime_bool_set", "", "static", "false", okSlot));
            AddRuntimeAction(new RuntimeAction("runtime_int_set", "", "slot", index.Value, indexSlot));
            for (var i = 0; i < array.Size; i++)
            {
                AddRuntimeAction(new RuntimeAction("runtime_if_int", "eq", "static", i.ToString(CultureInfo.InvariantCulture), indexSlot));
                emitForIndex(i);
                AddRuntimeAction(new RuntimeAction("runtime_bool_set", "", "static", "true", okSlot));
                AddRuntimeAction(new RuntimeAction("runtime_if_end", "", "static", "", ""));
            }
            AddRuntimeAction(new RuntimeAction("runtime_trap_if_bool_false", "", "static", "", okSlot));
        }

        static string RuntimeArrayDefaultValue(string runtimeType)
            => runtimeType switch
            {
                "int" => "0",
                "bool" => "false",
                "string" => "",
                _ when IsRuntimeEnumParamType(runtimeType) => "0",
                _ => ""
            };

        static string RuntimeTypeToSymbolType(string runtimeType)
            => runtimeType == "string" ? "text" : runtimeType;

        static string RuntimeParamSlotName(string functionName, string paramName)
            => "__fn_" + SanitizeInternalName(functionName) + "_param_" + SanitizeInternalName(paramName);

        static string RuntimeLocalSlotName(string functionName, string localName)
            => "__fn_" + SanitizeInternalName(functionName) + "_local_" + SanitizeInternalName(localName);

        static string SanitizeInternalName(string value)
        {
            var sb = new StringBuilder();
            foreach (var ch in value)
                sb.Append(char.IsLetterOrDigit(ch) || ch == '_' ? ch : '_');
            return sb.Length == 0 ? "anon" : sb.ToString();
        }

        void ParseRuntimeBreakStatement(bool apply, bool inIf)
        {
            ExpectWord("break", "P124", "Expected break.");
            ExpectLine();
            if (_runtimeWhileParseDepth <= 0)
                throw new CompileError("SEMANTIC", "S138", Current.Line, Current.Column, "break is only supported inside runtime while blocks.");
            if (apply)
                AddRuntimeAction(new RuntimeAction("runtime_break", "", "static", "", ""));
        }

        void ParseRuntimeContinueStatement(bool apply, bool inIf)
        {
            ExpectWord("continue", "P125", "Expected continue.");
            ExpectLine();
            if (_runtimeWhileParseDepth <= 0)
                throw new CompileError("SEMANTIC", "S139", Current.Line, Current.Column, "continue is only supported inside runtime while blocks.");
            if (apply)
                AddRuntimeAction(new RuntimeAction("runtime_continue", "", "static", "", ""));
        }

        void ParseLocalRuntimeDefinition(bool apply)
        {
            var defineTok = Current;
            ExpectKeyword("define");
            ExpectWord("local", "P144", "Expected local runtime declaration.");
            ExpectWord("runtime", "P144", "Expected runtime after define local.");

            if (!CapturingRuntimeFunctionActions() || string.IsNullOrWhiteSpace(_currentRuntimeFunctionName))
                throw new CompileError("SEMANTIC", "S170", defineTok.Line, defineTok.Column, "define local runtime is only supported inside function bodies in M43.");

            if (CurrentWordIs("record"))
            {
                ParseLocalRuntimeRecordDefinition(defineTok, apply);
                return;
            }

            if (CurrentWordIs("enum"))
            {
                ParseLocalRuntimeEnumDefinition(defineTok, apply);
                return;
            }

            if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                throw new CompileError("PARSE", "P144", Current.Line, Current.Column, "Local runtime declarations support int, bool, string slots, arrays, records, and enums.");

            var declaredType = Advance().Value;
            if (CurrentWordIs("array"))
            {
                ParseLocalRuntimeArrayDefinition(defineTok, declaredType, apply);
                return;
            }
            if (!IsKeyword("called"))
                throw new CompileError("PARSE", "P071", Current.Line, Current.Column, $"Expected keyword \"called\" after define local runtime {declaredType}.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", $"local runtime {declaredType} symbol name");

            if (_runtimeFunctionParamNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S171", nameTok.Line, nameTok.Column, $"Local runtime symbol \"{nameTok.Value}\" conflicts with a function parameter in M43.");
            if (_runtimeArrays.ContainsKey(nameTok.Value))
                throw new CompileError("SEMANTIC", "S185", nameTok.Line, nameTok.Column, $"Local runtime symbol \"{nameTok.Value}\" conflicts with a runtime array in M47/M48.");
            if (!_runtimeFunctionLocalNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S172", nameTok.Line, nameTok.Column, $"Duplicate local runtime symbol \"{nameTok.Value}\" in function \"{_currentRuntimeFunctionName}\".");

            if (!IsKeyword("be"))
                throw new CompileError("PARSE", "P073", Current.Line, Current.Column, $"Expected keyword \"be\" after local runtime {declaredType} symbol name.");
            ExpectKeyword("be");

            var parsed = declaredType switch
            {
                "int" => ParseRuntimeIntLiteral("define local runtime int"),
                "bool" => ParseRuntimeBoolLiteral("define local runtime bool"),
                "string" => ParseRuntimeStringStaticLiteral("define local runtime string"),
                _ => throw new CompileError("PARSE", "P144", Current.Line, Current.Column, "Unsupported local runtime slot type.")
            };

            ExpectLine();

            var slot = RuntimeLocalSlotName(_currentRuntimeFunctionName!, nameTok.Value);
            if (_runtimeFunctionSavedLocalSymbols != null && !_runtimeFunctionSavedLocalSymbols.ContainsKey(nameTok.Value) && _vars.TryGetValue(nameTok.Value, out var existing))
                _runtimeFunctionSavedLocalSymbols[nameTok.Value] = existing;

            _runtimeParamAliases[nameTok.Value] = slot;
            _vars[nameTok.Value] = new VarInfo(RuntimeTypeToSymbolType(declaredType), slot, IsRuntime: true);
            _currentRuntimeFunctionLocals?.Add(new RuntimeLocal(nameTok.Value, declaredType, slot));
            AddRuntimeAction(new RuntimeAction($"runtime_{declaredType}_set", "", parsed.Kind, parsed.Value, slot));
        }

        void SaveRuntimeArrayForFunctionScope(string name)
        {
            if (_runtimeFunctionSavedLocalArrays == null || _runtimeFunctionSavedLocalArrays.ContainsKey(name))
                return;
            if (_runtimeArrays.TryGetValue(name, out var existing))
                _runtimeFunctionSavedLocalArrays[name] = existing;
        }

        void SaveRuntimeRecordForFunctionScope(string name)
        {
            if (_runtimeFunctionSavedLocalRecords == null || _runtimeFunctionSavedLocalRecords.ContainsKey(name))
                return;
            if (_runtimeRecordInstances.TryGetValue(name, out var existing))
                _runtimeFunctionSavedLocalRecords[name] = existing;
        }

        void SaveRuntimeEnumForFunctionScope(string name)
        {
            if (_runtimeFunctionSavedLocalEnums == null || _runtimeFunctionSavedLocalEnums.ContainsKey(name))
                return;
            if (_runtimeEnumInstances.TryGetValue(name, out var existing))
                _runtimeFunctionSavedLocalEnums[name] = existing;
        }

        void SaveRuntimeEnumArrayForFunctionScope(string name)
        {
            if (_runtimeFunctionSavedLocalEnumArrays == null || _runtimeFunctionSavedLocalEnumArrays.ContainsKey(name))
                return;
            if (_runtimeEnumArrays.TryGetValue(name, out var existing))
                _runtimeFunctionSavedLocalEnumArrays[name] = existing;
        }

        void ParseLocalRuntimeEnumDefinition(Token defineTok, bool apply)
        {
            ExpectWord("enum", "P188", "Expected enum after define local runtime.");
            if (!CapturingRuntimeFunctionActions() || string.IsNullOrWhiteSpace(_currentRuntimeFunctionName))
                throw new CompileError("SEMANTIC", "S226", defineTok.Line, defineTok.Column, "define local runtime enum is only supported inside function bodies in M61.");

            if (CurrentWordIs("array"))
            {
                ParseLocalRuntimeEnumArrayDefinition(defineTok, apply);
                return;
            }

            if (IsKeyword("called"))
                ExpectKeyword("called");
            var nameTok = Expect("STRING", "local runtime enum name");
            if (_runtimeFunctionParamNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S227", nameTok.Line, nameTok.Column, $"Local runtime enum \"{nameTok.Value}\" conflicts with a function parameter in M61.");
            if (!_runtimeFunctionLocalNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S228", nameTok.Line, nameTok.Column, $"Duplicate local runtime symbol, array, record, or enum \"{nameTok.Value}\" in function \"{_currentRuntimeFunctionName}\".");

            ExpectKeyword("from");
            var typeTok = Expect("STRING", "local runtime enum type name");
            if (!_runtimeEnumTypes.TryGetValue(typeTok.Value, out var enumType))
                throw new CompileError("SEMANTIC", "S217", typeTok.Line, typeTok.Column, $"Runtime enum type \"{typeTok.Value}\" is not defined.");
            ExpectKeyword("be");
            var valueTok = Expect("STRING", "local runtime enum initial value");
            var index = RuntimeEnumValueIndex(enumType, valueTok, "define local runtime enum");
            ExpectLine();

            if (!apply)
                return;

            SaveRuntimeEnumForFunctionScope(nameTok.Value);
            var instance = new RuntimeEnumInstance(nameTok.Value, enumType.Name, RuntimeLocalSlotName(_currentRuntimeFunctionName!, nameTok.Value));
            _runtimeEnumInstances[nameTok.Value] = instance;
            _currentRuntimeFunctionLocals?.Add(new RuntimeLocal(nameTok.Value, "enum:" + enumType.Name, instance.Slot));
            AddRuntimeAction(new RuntimeAction("runtime_int_set", "", "static", index.ToString(CultureInfo.InvariantCulture), RuntimeEnumStorageName(instance)));
        }

        void ParseLocalRuntimeEnumArrayDefinition(Token defineTok, bool apply)
        {
            ExpectWord("array", "P189", "Expected array after define local runtime enum.");
            if (!CapturingRuntimeFunctionActions() || string.IsNullOrWhiteSpace(_currentRuntimeFunctionName))
                throw new CompileError("SEMANTIC", "S229", defineTok.Line, defineTok.Column, "define local runtime enum array is only supported inside function bodies in M61.");

            ExpectKeyword("called");
            var nameTok = Expect("STRING", "local runtime enum array name");
            if (_runtimeFunctionParamNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S230", nameTok.Line, nameTok.Column, $"Local runtime enum array \"{nameTok.Value}\" conflicts with a function parameter in M61.");
            if (!_runtimeFunctionLocalNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S231", nameTok.Line, nameTok.Column, $"Duplicate local runtime symbol, array, record, or enum array \"{nameTok.Value}\" in function \"{_currentRuntimeFunctionName}\".");

            ExpectKeyword("from");
            var typeTok = Expect("STRING", "local runtime enum array type name");
            if (!_runtimeEnumTypes.TryGetValue(typeTok.Value, out var enumType))
                throw new CompileError("SEMANTIC", "S217", typeTok.Line, typeTok.Column, $"Runtime enum type \"{typeTok.Value}\" is not defined.");
            ExpectWord("size", "P189", "Expected size after local runtime enum array type.");
            var sizeTok = Expect("INT", "local runtime enum array size");
            if (!int.TryParse(sizeTok.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var size))
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Local runtime enum array size must fit i32: {sizeTok.Value}.");
            if (size <= 0)
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, "Local runtime enum array size must be positive.");
            if (size > 1024)
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, "Local runtime enum array size is capped at 1024 in M61.");
            ExpectLine();

            if (!apply)
                return;

            SaveRuntimeEnumArrayForFunctionScope(nameTok.Value);
            var info = new RuntimeEnumArrayInfo(nameTok.Value, enumType.Name, size, RuntimeLocalArraySlotName(_currentRuntimeFunctionName!, nameTok.Value));
            _runtimeEnumArrays[nameTok.Value] = info;
            _currentRuntimeFunctionLocals?.Add(new RuntimeLocal(nameTok.Value, "enum_array:" + enumType.Name, info.Slot));
            for (var i = 0; i < size; i++)
                AddRuntimeAction(new RuntimeAction("runtime_int_set", "", "static", "0", RuntimeEnumArrayElementSlotName(info, i)));
        }

        void ParseLocalRuntimeRecordDefinition(Token defineTok, bool apply)
        {
            ExpectWord("record", "P165", "Expected record after define local runtime.");
            if (!CapturingRuntimeFunctionActions() || string.IsNullOrWhiteSpace(_currentRuntimeFunctionName))
                throw new CompileError("SEMANTIC", "S202", defineTok.Line, defineTok.Column, "define local runtime record is only supported inside function bodies in M53.");

            var nameTok = Expect("STRING", "local runtime record name");
            if (_runtimeFunctionParamNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S203", nameTok.Line, nameTok.Column, $"Local runtime record \"{nameTok.Value}\" conflicts with a function parameter in M53.");
            if (!_runtimeFunctionLocalNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S204", nameTok.Line, nameTok.Column, $"Duplicate local runtime symbol, array, or record \"{nameTok.Value}\" in function \"{_currentRuntimeFunctionName}\".");

            ExpectKeyword("from");
            var typeTok = Expect("STRING", "local runtime record type name");
            if (!_runtimeRecordTypes.TryGetValue(typeTok.Value, out var recordType))
                throw new CompileError("SEMANTIC", "S198", typeTok.Line, typeTok.Column, $"Runtime record type \"{typeTok.Value}\" is not defined.");
            ExpectLine();

            if (!apply)
                return;

            SaveRuntimeRecordForFunctionScope(nameTok.Value);
            var instance = new RuntimeRecordInstance(nameTok.Value, recordType.Name, recordType.Fields, RuntimeLocalRecordSlotName(_currentRuntimeFunctionName!, nameTok.Value));
            _runtimeRecordInstances[nameTok.Value] = instance;
            _currentRuntimeFunctionLocals?.Add(new RuntimeLocal(nameTok.Value, "record:" + recordType.Name, instance.Slot));
            foreach (var field in recordType.Fields)
                AddRuntimeAction(new RuntimeAction($"runtime_{RuntimeStorageActionType(field.Type)}_set", "", "static", RuntimeArrayDefaultValue(field.Type), RuntimeRecordFieldSlotName(instance, field.Name)));
        }

        void ParseLocalRuntimeArrayDefinition(Token defineTok, string declaredType, bool apply)
        {
            ExpectWord("array", "P155", $"Expected array after define local runtime {declaredType}.");
            if (!CapturingRuntimeFunctionActions() || string.IsNullOrWhiteSpace(_currentRuntimeFunctionName))
                throw new CompileError("SEMANTIC", "S186", defineTok.Line, defineTok.Column, "define local runtime array is only supported inside function bodies in M49.");

            ExpectKeyword("called");
            var nameTok = Expect("STRING", $"local runtime {declaredType} array name");
            if (_runtimeFunctionParamNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S187", nameTok.Line, nameTok.Column, $"Local runtime array \"{nameTok.Value}\" conflicts with a function parameter in M49.");
            if (!_runtimeFunctionLocalNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S188", nameTok.Line, nameTok.Column, $"Duplicate local runtime symbol or array \"{nameTok.Value}\" in function \"{_currentRuntimeFunctionName}\".");

            ExpectWord("size", "P155", $"Expected size after local runtime {declaredType} array name.");
            var sizeTok = Expect("INT", $"local runtime {declaredType} array size");
            if (!int.TryParse(sizeTok.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var size))
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Local runtime {declaredType} array size must fit i32: {sizeTok.Value}.");
            if (size <= 0)
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Local runtime {declaredType} array size must be positive.");
            if (size > 1024)
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Local runtime {declaredType} array size is capped at 1024 in M49.");
            ExpectLine();

            if (!apply)
                return;

            SaveRuntimeArrayForFunctionScope(nameTok.Value);
            var info = new RuntimeArrayInfo(nameTok.Value, declaredType, size, RuntimeLocalArraySlotName(_currentRuntimeFunctionName!, nameTok.Value));
            _runtimeArrays[nameTok.Value] = info;
            _currentRuntimeFunctionLocals?.Add(new RuntimeLocal(nameTok.Value, declaredType + "_array", info.Slot));
            for (var i = 0; i < size; i++)
                AddRuntimeAction(new RuntimeAction($"runtime_{declaredType}_set", "", "static", RuntimeArrayDefaultValue(declaredType), RuntimeArrayElementSlotName(info, i)));
        }

        void ParseRuntimeArrayDefinitionStatement(bool apply, bool inIf)
        {
            ExpectKeyword("define");
            ExpectWord("runtime", "P150", "Expected runtime after define.");
            if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                throw new CompileError("PARSE", "P150", Current.Line, Current.Column, "Expected runtime array type: int, bool, or string.");
            var declaredType = Advance().Value;
            ExpectWord("array", "P150", $"Expected array after define runtime {declaredType}.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", $"runtime {declaredType} array name");
            CheckDuplicateSymbol(nameTok, $"Runtime {declaredType} array");
            ExpectWord("size", "P150", $"Expected size after runtime {declaredType} array name.");
            var sizeTok = Expect("INT", $"runtime {declaredType} array size");
            if (!int.TryParse(sizeTok.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var size))
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Runtime {declaredType} array size must fit i32: {sizeTok.Value}.");
            if (size <= 0)
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Runtime {declaredType} array size must be positive.");
            if (size > 1024)
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Runtime {declaredType} array size is capped at 1024 in M47/M48.");
            ExpectLine();

            if (!apply)
                return;

            var info = new RuntimeArrayInfo(nameTok.Value, declaredType, size);
            _runtimeArrays[nameTok.Value] = info;
            if (declaredType == "int")
                _runtimeIntArrays[nameTok.Value] = new RuntimeIntArrayInfo(nameTok.Value, size);
            _flow.Add($"RUNTIME_{declaredType.ToUpperInvariant()}_ARRAY|name={nameTok.Value}|size={size}");
            for (var i = 0; i < size; i++)
                AddRuntimeAction(new RuntimeAction($"runtime_{declaredType}_set", "", "static", RuntimeArrayDefaultValue(declaredType), RuntimeArrayElementSlotName(info, i)));
        }

        void ParseRuntimeArraySetStatement(bool apply, bool inIf)
        {
            ExpectKeyword("set");
            ExpectWord("runtime", "P152", "Expected runtime after set.");
            if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                throw new CompileError("PARSE", "P152", Current.Line, Current.Column, "Expected runtime array set type: int, bool, or string.");
            var declaredType = Advance().Value;
            ExpectWord("array", "P152", $"Expected array after set runtime {declaredType}.");
            var arrayTok = Expect("STRING", $"runtime {declaredType} array name");
            var array = RequireRuntimeArray(arrayTok, declaredType, "S184", $"set runtime {declaredType} array");
            var index = ParseRuntimeArrayIndex(array, $"set runtime {declaredType} array");
            ExpectKeyword("to");
            var value = declaredType switch
            {
                "int" => ParseRuntimeIntOperand("set runtime int array value"),
                "bool" => ParseRuntimeBoolOperand("set runtime bool array value"),
                "string" => ParseRuntimeStringOperand("set runtime string array value"),
                _ => throw new CompileError("PARSE", "P152", Current.Line, Current.Column, "Unsupported runtime array set type.")
            };
            ExpectLine();

            if (!apply)
                return;

            AddRuntimeArrayBoundsCheckedDispatch(array, index, i =>
                AddRuntimeAction(new RuntimeAction($"runtime_{declaredType}_set", "", value.Kind, value.Value, RuntimeArrayElementSlotName(array, i))));
        }

        (RuntimeArrayInfo Array, RuntimeArrayIndex Index) ParseRuntimeArrayReadExpression(string declaredType, string context)
        {
            ExpectWord("runtime", "P153", "Expected runtime array expression.");
            ExpectKeyword(declaredType);
            ExpectWord("array", "P153", $"Expected array after runtime {declaredType}.");
            var arrayTok = Expect("STRING", $"runtime {declaredType} array name");
            var array = RequireRuntimeArray(arrayTok, declaredType, "S184", context);
            var index = ParseRuntimeArrayIndex(array, context);
            return (array, index);
        }

        void AddRuntimeArrayGetActions(RuntimeArrayInfo array, RuntimeArrayIndex index, string targetSlot)
        {
            AddRuntimeArrayBoundsCheckedDispatch(array, index, i =>
                AddRuntimeAction(new RuntimeAction($"runtime_{array.Type}_set", "", "slot", RuntimeArrayElementSlotName(array, i), targetSlot)));
        }

        RuntimeArrayInfo ParseRuntimeArrayLengthExpression(string context)
        {
            ExpectWord("length", "P154", "Expected length expression.");
            ExpectKeyword("of");
            ExpectWord("runtime", "P154", "Expected runtime after length of.");

            if (CurrentWordIs("enum"))
            {
                ExpectWord("enum", "P154", "Expected enum after runtime.");
                ExpectWord("array", "P154", "Expected array after runtime enum.");
                var arrayTok = Expect("STRING", "runtime enum array name");
                var enumArray = RequireRuntimeEnumArray(arrayTok, context);
                return new RuntimeArrayInfo(enumArray.Name, "int", enumArray.Size, RuntimeEnumArrayStorageName(enumArray));
            }

            if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                throw new CompileError("PARSE", "P154", Current.Line, Current.Column, "Array length supports runtime int/bool/string arrays and runtime enum arrays.");
            var arrayType = Advance().Value;
            ExpectWord("array", "P154", $"Expected array after runtime {arrayType}.");
            var arrayTok2 = Expect("STRING", $"runtime {arrayType} array name");
            return RequireRuntimeArray(arrayTok2, arrayType, "S184", context);
        }

        void ParseRuntimeArrayFillStatement(bool apply, bool inIf)
        {
            ExpectWord("fill", "P158", "Expected fill runtime array statement.");
            ExpectWord("runtime", "P158", "Expected runtime after fill.");
            if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                throw new CompileError("PARSE", "P158", Current.Line, Current.Column, "fill runtime array supports int, bool, and string arrays.");
            var declaredType = Advance().Value;
            ExpectWord("array", "P158", $"Expected array after fill runtime {declaredType}.");
            var arrayTok = Expect("STRING", $"fill runtime {declaredType} array name");
            var array = RequireRuntimeArray(arrayTok, declaredType, "S184", $"fill runtime {declaredType} array");
            ExpectKeyword("with");
            var value = ParseRuntimeTypedOperand(declaredType, $"fill runtime {declaredType} array value");
            ExpectLine();

            if (!apply)
                return;

            for (var i = 0; i < array.Size; i++)
                AddRuntimeAction(new RuntimeAction($"runtime_{declaredType}_set", "", value.Kind, value.Value, RuntimeArrayElementSlotName(array, i)));
        }

        void ParseRuntimeArrayCopyStatement(bool apply, bool inIf)
        {
            ExpectWord("copy", "P159", "Expected copy runtime array statement.");
            ExpectWord("runtime", "P159", "Expected runtime after copy.");
            if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                throw new CompileError("PARSE", "P159", Current.Line, Current.Column, "copy runtime array supports int, bool, and string arrays.");
            var declaredType = Advance().Value;
            ExpectWord("array", "P159", $"Expected array after copy runtime {declaredType}.");
            var sourceTok = Expect("STRING", $"copy runtime {declaredType} array source name");
            var source = RequireRuntimeArray(sourceTok, declaredType, "S184", $"copy runtime {declaredType} array source");
            ExpectKeyword("to");
            ExpectWord("runtime", "P159", "Expected runtime before destination array.");
            if (!CurrentIs("KEYWORD") || Current.Value != declaredType)
                throw new CompileError("SEMANTIC", "S193", Current.Line, Current.Column, $"copy runtime {declaredType} array destination must be runtime {declaredType} array.");
            Advance();
            ExpectWord("array", "P159", $"Expected array after destination runtime {declaredType}.");
            var destTok = Expect("STRING", $"copy runtime {declaredType} array destination name");
            var dest = RequireRuntimeArray(destTok, declaredType, "S184", $"copy runtime {declaredType} array destination");
            ExpectLine();

            if (source.Size != dest.Size)
                throw new CompileError("SEMANTIC", "S194", destTok.Line, destTok.Column, $"copy runtime {declaredType} arrays require matching sizes: source has {source.Size}, destination has {dest.Size}.");

            if (!apply)
                return;

            for (var i = 0; i < source.Size; i++)
                AddRuntimeAction(new RuntimeAction($"runtime_{declaredType}_set", "", "slot", RuntimeArrayElementSlotName(source, i), RuntimeArrayElementSlotName(dest, i)));
        }

        void ParseRuntimeRecordCopyStatement(bool apply, bool inIf)
        {
            ExpectWord("copy", "P171", "Expected copy runtime record statement.");
            ExpectWord("runtime", "P171", "Expected runtime after copy.");
            ExpectWord("record", "P171", "Expected record after copy runtime.");

            if (CurrentWordIs("array"))
            {
                ExpectWord("array", "P171", "Expected array after copy runtime record.");
                var sourceTok = Expect("STRING", "copy runtime record array source name");
                var source = RequireRuntimeRecordArray(sourceTok, "copy runtime record array source");
                ExpectKeyword("to");
                ExpectWord("runtime", "P171", "Expected runtime before destination record array.");
                ExpectWord("record", "P171", "Expected record before destination record array.");
                ExpectWord("array", "P171", "Expected array before destination record array name.");
                var destTok = Expect("STRING", "copy runtime record array destination name");
                var dest = RequireRuntimeRecordArray(destTok, "copy runtime record array destination");
                ExpectLine();

                if (source.TypeName != dest.TypeName)
                    throw new CompileError("SEMANTIC", "S211", destTok.Line, destTok.Column, $"copy runtime record array requires matching record types: source is {source.TypeName}, destination is {dest.TypeName}.");
                if (source.Size != dest.Size)
                    throw new CompileError("SEMANTIC", "S212", destTok.Line, destTok.Column, $"copy runtime record array requires matching sizes: source has {source.Size}, destination has {dest.Size}.");

                if (!apply)
                    return;

                for (var i = 0; i < source.Size; i++)
                    foreach (var field in source.Fields)
                        AddRuntimeAction(new RuntimeAction($"runtime_{RuntimeStorageActionType(field.Type)}_set", "", "slot", RuntimeRecordArrayFieldSlotName(source, i, field.Name), RuntimeRecordArrayFieldSlotName(dest, i, field.Name)));
                return;
            }

            var sourceRecordTok = Expect("STRING", "copy runtime record source name");
            var sourceRecord = RequireRuntimeRecord(sourceRecordTok, "copy runtime record source");
            ExpectKeyword("to");
            ExpectWord("runtime", "P171", "Expected runtime before destination record.");
            ExpectWord("record", "P171", "Expected record before destination record name.");
            var destRecordTok = Expect("STRING", "copy runtime record destination name");
            var destRecord = RequireRuntimeRecord(destRecordTok, "copy runtime record destination");
            ExpectLine();

            if (sourceRecord.TypeName != destRecord.TypeName)
                throw new CompileError("SEMANTIC", "S211", destRecordTok.Line, destRecordTok.Column, $"copy runtime record requires matching record types: source is {sourceRecord.TypeName}, destination is {destRecord.TypeName}.");

            if (!apply)
                return;

            foreach (var field in sourceRecord.Fields)
                AddRuntimeAction(new RuntimeAction($"runtime_{RuntimeStorageActionType(field.Type)}_set", "", "slot", RuntimeRecordFieldSlotName(sourceRecord, field.Name), RuntimeRecordFieldSlotName(destRecord, field.Name)));
        }

        void ParseRuntimeRecordResetStatement(bool apply, bool inIf)
        {
            ExpectWord("reset", "P172", "Expected reset runtime record statement.");
            ExpectWord("runtime", "P172", "Expected runtime after reset.");
            ExpectWord("record", "P172", "Expected record after reset runtime.");

            if (CurrentWordIs("array"))
            {
                ExpectWord("array", "P172", "Expected array after reset runtime record.");
                var arrayTok = Expect("STRING", "reset runtime record array name");
                var array = RequireRuntimeRecordArray(arrayTok, "reset runtime record array");
                ExpectLine();

                if (!apply)
                    return;

                for (var i = 0; i < array.Size; i++)
                    foreach (var field in array.Fields)
                        AddRuntimeAction(new RuntimeAction($"runtime_{RuntimeStorageActionType(field.Type)}_set", "", "static", RuntimeArrayDefaultValue(field.Type), RuntimeRecordArrayFieldSlotName(array, i, field.Name)));
                return;
            }

            var recordTok = Expect("STRING", "reset runtime record name");
            var record = RequireRuntimeRecord(recordTok, "reset runtime record");
            ExpectLine();

            if (!apply)
                return;

            foreach (var field in record.Fields)
                AddRuntimeAction(new RuntimeAction($"runtime_{RuntimeStorageActionType(field.Type)}_set", "", "static", RuntimeArrayDefaultValue(field.Type), RuntimeRecordFieldSlotName(record, field.Name)));
        }

        static string RuntimeEnumSlotName(string enumName)
            => "__enum_" + SanitizeInternalName(enumName);

        static string RuntimeEnumStorageName(RuntimeEnumInstance instance)
            => string.IsNullOrWhiteSpace(instance.Slot) ? RuntimeEnumSlotName(instance.Name) : instance.Slot;

        RuntimeEnumInstance RequireRuntimeEnum(Token enumTok, string context)
        {
            if (_runtimeEnumInstances.TryGetValue(enumTok.Value, out var instance))
                return instance;
            throw new CompileError("SEMANTIC", "S213", enumTok.Line, enumTok.Column, $"{context} references unknown runtime enum \"{enumTok.Value}\".");
        }

        int RuntimeEnumValueIndex(RuntimeEnumType enumType, Token valueTok, string context)
        {
            var index = enumType.Values.FindIndex(v => v == valueTok.Value);
            if (index < 0)
                throw new CompileError("SEMANTIC", "S214", valueTok.Line, valueTok.Column, $"{context} references unknown enum value \"{valueTok.Value}\" for enum \"{enumType.Name}\".");
            return index;
        }

        (string Kind, string Value) ParseRuntimeEnumOperand(RuntimeEnumType enumType, string context)
        {
            if (CurrentWordIs("runtime"))
            {
                ExpectWord("runtime", "P175", "Expected runtime enum source.");
                ExpectWord("enum", "P175", "Expected enum after runtime.");
                var enumTok = Expect("STRING", "runtime enum source name");
                var source = RequireRuntimeEnum(enumTok, context);
                if (source.TypeName != enumType.Name)
                    throw new CompileError("SEMANTIC", "S215", enumTok.Line, enumTok.Column, $"{context} expects enum {enumType.Name}, but source enum \"{enumTok.Value}\" is {source.TypeName}.");
                return ("slot", RuntimeEnumStorageName(source));
            }

            var valueTok = Expect("STRING", "runtime enum value name");
            var index = RuntimeEnumValueIndex(enumType, valueTok, context);
            return ("static", index.ToString(CultureInfo.InvariantCulture));
        }

        void ParseRuntimeEnumTypeDefinitionStatement(bool apply, bool inIf)
        {
            ExpectKeyword("define");
            ExpectWord("enum", "P173", "Expected enum after define.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "enum type name");
            CheckDuplicateSymbol(nameTok, "Runtime enum type");
            ExpectKeyword("with");

            var values = new List<string>();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            while (true)
            {
                var valueTok = Expect("STRING", "enum value name");
                if (string.IsNullOrWhiteSpace(valueTok.Value))
                    throw new CompileError("SEMANTIC", "S216", valueTok.Line, valueTok.Column, "Enum values cannot be empty.");
                if (!seen.Add(valueTok.Value))
                    throw new CompileError("SEMANTIC", "S216", valueTok.Line, valueTok.Column, $"Duplicate enum value \"{valueTok.Value}\" in enum \"{nameTok.Value}\".");
                values.Add(valueTok.Value);

                if (CurrentIs("COMMA"))
                {
                    Advance();
                    continue;
                }
                if (IsKeyword("and"))
                {
                    ExpectKeyword("and");
                    continue;
                }
                break;
            }

            if (values.Count == 0)
                throw new CompileError("SEMANTIC", "S216", nameTok.Line, nameTok.Column, "Enum types require at least one value.");
            ExpectLine();

            if (!apply)
                return;

            _runtimeEnumTypes[nameTok.Value] = new RuntimeEnumType(nameTok.Value, values);
            _flow.Add($"RUNTIME_ENUM_TYPE|name={nameTok.Value}|values={string.Join(",", values)}");
        }

        void ParseRuntimeEnumInstanceDefinitionStatement(bool apply, bool inIf)
        {
            ExpectKeyword("define");
            ExpectWord("runtime", "P174", "Expected runtime after define.");
            ExpectWord("enum", "P174", "Expected enum after define runtime.");
            var nameTok = Expect("STRING", "runtime enum name");
            CheckDuplicateSymbol(nameTok, "Runtime enum");
            ExpectKeyword("from");
            var typeTok = Expect("STRING", "runtime enum type name");
            if (!_runtimeEnumTypes.TryGetValue(typeTok.Value, out var enumType))
                throw new CompileError("SEMANTIC", "S217", typeTok.Line, typeTok.Column, $"Runtime enum type \"{typeTok.Value}\" is not defined.");
            ExpectKeyword("be");
            var valueTok = Expect("STRING", "runtime enum initial value");
            var index = RuntimeEnumValueIndex(enumType, valueTok, "define runtime enum");
            ExpectLine();

            if (!apply)
                return;

            var instance = new RuntimeEnumInstance(nameTok.Value, enumType.Name, RuntimeEnumSlotName(nameTok.Value));
            _runtimeEnumInstances[nameTok.Value] = instance;
            _flow.Add($"RUNTIME_ENUM|name={nameTok.Value}|type={enumType.Name}|slot={instance.Slot}");
            AddRuntimeAction(new RuntimeAction("runtime_int_set", "", "static", index.ToString(CultureInfo.InvariantCulture), RuntimeEnumStorageName(instance)));
        }

        void ParseRuntimeEnumSetStatement(bool apply, bool inIf)
        {
            ExpectKeyword("set");
            ExpectWord("runtime", "P175", "Expected runtime after set.");
            ExpectWord("enum", "P175", "Expected enum after set runtime.");
            var enumTok = Expect("STRING", "runtime enum name");
            var instance = RequireRuntimeEnum(enumTok, "set runtime enum");
            if (!_runtimeEnumTypes.TryGetValue(instance.TypeName, out var enumType))
                throw new CompileError("SEMANTIC", "S217", enumTok.Line, enumTok.Column, $"Runtime enum type \"{instance.TypeName}\" is not defined.");
            ExpectKeyword("to");

            if (IsKeyword("call"))
            {
                var call = ParseFunctionCallExpression();
                ExpectLine();

                if (!apply)
                    return;

                if (!_runtimeFunctionMap.TryGetValue(call.Name, out var fn))
                    throw new CompileError("SEMANTIC", "S050", call.NameToken.Line, call.NameToken.Column, $"Unknown function \"{call.Name}\".");
                var expectedReturn = "enum:" + enumType.Name;
                if (fn.ReturnType == "void")
                    throw new CompileError("SEMANTIC", "S162", call.NameToken.Line, call.NameToken.Column, $"Function \"{call.Name}\" returns void and cannot be assigned to a runtime enum slot.");
                if (fn.ReturnType != expectedReturn)
                    throw new CompileError("SEMANTIC", "S163", call.NameToken.Line, call.NameToken.Column, $"Function \"{call.Name}\" returns {fn.ReturnType}, not {expectedReturn}.");

                AddFunctionArgumentSetupActions(fn, call.Args, call.NameToken);
                AddRuntimeAction(new RuntimeAction("function_call_assign", "int", "static", call.Name, RuntimeEnumStorageName(instance)));
                AddFunctionArgumentCopyBackActions(fn, call.Args, call.NameToken);
                return;
            }

            if (CurrentWordIs("runtime") && PeekWord("record") && PeekWord("array", 2))
            {
                var read = ParseRuntimeRecordArrayFieldReadExpression("enum:" + enumType.Name, "set runtime enum from record array field");
                ExpectLine();

                if (!apply)
                    return;

                AddRuntimeRecordArrayBoundsCheckedDispatch(read.Array, read.Index, i =>
                    AddRuntimeAction(new RuntimeAction("runtime_int_set", "", "slot", RuntimeRecordArrayFieldSlotName(read.Array, i, read.Field.Name), RuntimeEnumStorageName(instance))));
                return;
            }

            if (CurrentWordIs("runtime") && PeekWord("record") && PeekString(2) && PeekWord("field", 3))
            {
                var read = ParseRuntimeRecordFieldReadExpression("enum:" + enumType.Name, "set runtime enum from record field");
                ExpectLine();

                if (!apply)
                    return;

                AddRuntimeAction(new RuntimeAction("runtime_int_set", "", "slot", read.Slot, RuntimeEnumStorageName(instance)));
                return;
            }

            if (CurrentWordIs("runtime") && PeekWord("enum") && PeekWord("array", 2))
            {
                var read = ParseRuntimeEnumArrayReadExpression(enumType.Name, "set runtime enum from enum array");
                ExpectLine();

                if (!apply)
                    return;

                AddRuntimeEnumArrayBoundsCheckedDispatch(read.Array, read.Index, i =>
                    AddRuntimeAction(new RuntimeAction("runtime_int_set", "", "slot", RuntimeEnumArrayElementSlotName(read.Array, i), RuntimeEnumStorageName(instance))));
                return;
            }

            var value = ParseRuntimeEnumOperand(enumType, "set runtime enum");
            ExpectLine();

            if (!apply)
                return;

            AddRuntimeAction(new RuntimeAction("runtime_int_set", "", value.Kind, value.Value, RuntimeEnumStorageName(instance)));
        }

        (string Left, string ActionOp, string Op, string RightKind, string Right) ParseRuntimeEnumIfCondition()
        {
            ExpectWord("enum", "P176", "Expected enum after runtime if.");
            var enumTok = Expect("STRING", "runtime enum condition name");
            var instance = RequireRuntimeEnum(enumTok, "runtime if enum");
            if (!_runtimeEnumTypes.TryGetValue(instance.TypeName, out var enumType))
                throw new CompileError("SEMANTIC", "S217", enumTok.Line, enumTok.Column, $"Runtime enum type \"{instance.TypeName}\" is not defined.");

            var op = "eq";
            if (IsKeyword("is"))
            {
                ExpectKeyword("is");
                if (IsKeyword("not"))
                {
                    ExpectKeyword("not");
                    op = "ne";
                }
            }
            else if (CurrentWordIs("equals"))
            {
                ExpectWord("equals", "P176", "Expected runtime enum comparison operator.");
                op = "eq";
            }
            else
            {
                throw new CompileError("PARSE", "P176", Current.Line, Current.Column, "Runtime enum comparisons support is, is not, and equals.");
            }

            var right = ParseRuntimeEnumOperand(enumType, "runtime if enum");
            return (RuntimeEnumStorageName(instance), "runtime_if_int", op, right.Kind, right.Value);
        }

        static string RuntimeEnumArrayStorageName(RuntimeEnumArrayInfo array)
            => string.IsNullOrWhiteSpace(array.Slot) ? array.Name : array.Slot;

        static string RuntimeEnumArrayElementSlotName(string arrayStorageName, int index)
            => "__enumarr_" + SanitizeInternalName(arrayStorageName) + "_" + index.ToString(CultureInfo.InvariantCulture);

        static string RuntimeEnumArrayElementSlotName(RuntimeEnumArrayInfo array, int index)
            => RuntimeEnumArrayElementSlotName(RuntimeEnumArrayStorageName(array), index);

        RuntimeEnumArrayInfo RequireRuntimeEnumArray(Token arrayTok, string context)
        {
            if (_runtimeEnumArrays.TryGetValue(arrayTok.Value, out var array))
                return array;
            throw new CompileError("SEMANTIC", "S224", arrayTok.Line, arrayTok.Column, $"{context} references unknown runtime enum array \"{arrayTok.Value}\".");
        }

        RuntimeArrayIndex ParseRuntimeEnumArrayIndex(RuntimeEnumArrayInfo array, string context)
            => ParseRuntimeArrayIndex(new RuntimeArrayInfo(array.Name, "int", array.Size, RuntimeEnumArrayStorageName(array)), context);

        void AddRuntimeEnumArrayBoundsCheckedDispatch(RuntimeEnumArrayInfo array, RuntimeArrayIndex index, Action<int> emitForIndex)
            => AddRuntimeArrayBoundsCheckedDispatch(new RuntimeArrayInfo(array.Name, "int", array.Size, RuntimeEnumArrayStorageName(array)), index, emitForIndex);

        (RuntimeEnumArrayInfo Array, RuntimeArrayIndex Index) ParseRuntimeEnumArrayReadExpression(string enumTypeName, string context)
        {
            ExpectWord("runtime", "P182", "Expected runtime enum array expression.");
            ExpectWord("enum", "P182", "Expected enum after runtime.");
            ExpectWord("array", "P182", "Expected array after runtime enum.");
            var arrayTok = Expect("STRING", "runtime enum array name");
            var array = RequireRuntimeEnumArray(arrayTok, context);
            if (array.TypeName != enumTypeName)
                throw new CompileError("SEMANTIC", "S225", arrayTok.Line, arrayTok.Column, $"{context} expects runtime enum array of {enumTypeName}, but array \"{arrayTok.Value}\" is {array.TypeName}.");
            var index = ParseRuntimeEnumArrayIndex(array, context);
            return (array, index);
        }

        void ParseRuntimeEnumArrayDefinitionStatement(bool apply, bool inIf)
        {
            ExpectKeyword("define");
            ExpectWord("runtime", "P181", "Expected runtime after define.");
            ExpectWord("enum", "P181", "Expected enum after define runtime.");
            ExpectWord("array", "P181", "Expected array after define runtime enum.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "runtime enum array name");
            CheckDuplicateSymbol(nameTok, "Runtime enum array");
            ExpectKeyword("from");
            var typeTok = Expect("STRING", "runtime enum array type name");
            if (!_runtimeEnumTypes.ContainsKey(typeTok.Value))
                throw new CompileError("SEMANTIC", "S217", typeTok.Line, typeTok.Column, $"Runtime enum type \"{typeTok.Value}\" is not defined.");
            ExpectWord("size", "P181", "Expected size after runtime enum array type.");
            var sizeTok = Expect("INT", "runtime enum array size");
            if (!int.TryParse(sizeTok.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var size))
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Runtime enum array size must fit i32: {sizeTok.Value}.");
            if (size <= 0)
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, "Runtime enum array size must be positive.");
            if (size > 1024)
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, "Runtime enum array size is capped at 1024 in M60.");
            ExpectLine();

            if (!apply)
                return;

            var info = new RuntimeEnumArrayInfo(nameTok.Value, typeTok.Value, size);
            _runtimeEnumArrays[nameTok.Value] = info;
            _flow.Add($"RUNTIME_ENUM_ARRAY|name={nameTok.Value}|type={typeTok.Value}|size={size}");
            for (var i = 0; i < size; i++)
                AddRuntimeAction(new RuntimeAction("runtime_int_set", "", "static", "0", RuntimeEnumArrayElementSlotName(info, i)));
        }

        void ParseRuntimeEnumArraySetStatement(bool apply, bool inIf)
        {
            ExpectKeyword("set");
            ExpectWord("runtime", "P182", "Expected runtime after set.");
            ExpectWord("enum", "P182", "Expected enum after set runtime.");
            ExpectWord("array", "P182", "Expected array after set runtime enum.");
            var arrayTok = Expect("STRING", "runtime enum array name");
            var array = RequireRuntimeEnumArray(arrayTok, "set runtime enum array");
            if (!_runtimeEnumTypes.TryGetValue(array.TypeName, out var enumType))
                throw new CompileError("SEMANTIC", "S217", arrayTok.Line, arrayTok.Column, $"Runtime enum type \"{array.TypeName}\" is not defined.");
            var index = ParseRuntimeEnumArrayIndex(array, "set runtime enum array");
            ExpectKeyword("to");
            var value = ParseRuntimeEnumOperand(enumType, "set runtime enum array");
            ExpectLine();

            if (!apply)
                return;

            AddRuntimeEnumArrayBoundsCheckedDispatch(array, index, i =>
                AddRuntimeAction(new RuntimeAction("runtime_int_set", "", value.Kind, value.Value, RuntimeEnumArrayElementSlotName(array, i))));
        }

        void ParseRuntimeEnumArrayFillStatement(bool apply, bool inIf)
        {
            ExpectWord("fill", "P183", "Expected fill runtime enum array statement.");
            ExpectWord("runtime", "P183", "Expected runtime after fill.");
            ExpectWord("enum", "P183", "Expected enum after fill runtime.");
            ExpectWord("array", "P183", "Expected array after fill runtime enum.");
            var arrayTok = Expect("STRING", "fill runtime enum array name");
            var array = RequireRuntimeEnumArray(arrayTok, "fill runtime enum array");
            if (!_runtimeEnumTypes.TryGetValue(array.TypeName, out var enumType))
                throw new CompileError("SEMANTIC", "S217", arrayTok.Line, arrayTok.Column, $"Runtime enum type \"{array.TypeName}\" is not defined.");
            ExpectKeyword("with");
            var value = ParseRuntimeEnumOperand(enumType, "fill runtime enum array");
            ExpectLine();

            if (!apply)
                return;

            for (var i = 0; i < array.Size; i++)
                AddRuntimeAction(new RuntimeAction("runtime_int_set", "", value.Kind, value.Value, RuntimeEnumArrayElementSlotName(array, i)));
        }

        void ParseRuntimeEnumArrayCopyStatement(bool apply, bool inIf)
        {
            ExpectWord("copy", "P184", "Expected copy runtime enum array statement.");
            ExpectWord("runtime", "P184", "Expected runtime after copy.");
            ExpectWord("enum", "P184", "Expected enum after copy runtime.");
            ExpectWord("array", "P184", "Expected array after copy runtime enum.");
            var sourceTok = Expect("STRING", "copy runtime enum array source name");
            var source = RequireRuntimeEnumArray(sourceTok, "copy runtime enum array source");
            ExpectKeyword("to");
            ExpectWord("runtime", "P184", "Expected runtime before destination enum array.");
            ExpectWord("enum", "P184", "Expected enum before destination enum array.");
            ExpectWord("array", "P184", "Expected array before destination enum array name.");
            var destTok = Expect("STRING", "copy runtime enum array destination name");
            var dest = RequireRuntimeEnumArray(destTok, "copy runtime enum array destination");
            ExpectLine();

            if (source.TypeName != dest.TypeName)
                throw new CompileError("SEMANTIC", "S225", destTok.Line, destTok.Column, $"copy runtime enum array requires matching enum types: source is {source.TypeName}, destination is {dest.TypeName}.");
            if (source.Size != dest.Size)
                throw new CompileError("SEMANTIC", "S194", destTok.Line, destTok.Column, $"copy runtime enum arrays require matching sizes: source has {source.Size}, destination has {dest.Size}.");

            if (!apply)
                return;

            for (var i = 0; i < source.Size; i++)
                AddRuntimeAction(new RuntimeAction("runtime_int_set", "", "slot", RuntimeEnumArrayElementSlotName(source, i), RuntimeEnumArrayElementSlotName(dest, i)));
        }

        static string RuntimeRecordStorageName(RuntimeRecordInstance record)
            => string.IsNullOrWhiteSpace(record.Slot) ? record.Name : record.Slot;

        static string RuntimeRecordFieldSlotName(string recordStorageName, string fieldName)
            => "__rec_" + SanitizeInternalName(recordStorageName) + "_" + SanitizeInternalName(fieldName);

        static string RuntimeRecordFieldSlotName(RuntimeRecordInstance record, string fieldName)
            => RuntimeRecordFieldSlotName(RuntimeRecordStorageName(record), fieldName);

        static string RuntimeRecordArrayStorageName(RuntimeRecordArrayInfo array)
            => string.IsNullOrWhiteSpace(array.Slot) ? array.Name : array.Slot;

        static string RuntimeRecordArrayFieldSlotName(string arrayStorageName, int index, string fieldName)
            => "__recarr_" + SanitizeInternalName(arrayStorageName) + "_" + index.ToString(CultureInfo.InvariantCulture) + "_" + SanitizeInternalName(fieldName);

        static string RuntimeRecordArrayFieldSlotName(RuntimeRecordArrayInfo array, int index, string fieldName)
            => RuntimeRecordArrayFieldSlotName(RuntimeRecordArrayStorageName(array), index, fieldName);

        RuntimeRecordInstance RequireRuntimeRecord(Token recordTok, string context)
        {
            if (_runtimeRecordInstances.TryGetValue(recordTok.Value, out var record))
                return record;
            throw new CompileError("SEMANTIC", "S199", recordTok.Line, recordTok.Column, $"{context} references unknown runtime record \"{recordTok.Value}\".");
        }

        RuntimeRecordArrayInfo RequireRuntimeRecordArray(Token arrayTok, string context)
        {
            if (_runtimeRecordArrays.TryGetValue(arrayTok.Value, out var array))
                return array;
            throw new CompileError("SEMANTIC", "S205", arrayTok.Line, arrayTok.Column, $"{context} references unknown runtime record array \"{arrayTok.Value}\".");
        }

        RuntimeArrayIndex ParseRuntimeRecordArrayIndex(RuntimeRecordArrayInfo array, string context)
            => ParseRuntimeArrayIndex(new RuntimeArrayInfo(array.Name, "int", array.Size, RuntimeRecordArrayStorageName(array)), context);

        void AddRuntimeRecordArrayBoundsCheckedDispatch(RuntimeRecordArrayInfo array, RuntimeArrayIndex index, Action<int> emitForIndex)
            => AddRuntimeArrayBoundsCheckedDispatch(new RuntimeArrayInfo(array.Name, "int", array.Size, RuntimeRecordArrayStorageName(array)), index, emitForIndex);

        void ParseRuntimeRecordTypeDefinitionStatement(bool apply, bool inIf)
        {
            ExpectKeyword("define");
            ExpectWord("record", "P160", "Expected record after define.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "record type name");
            if (SymbolExists(nameTok.Value) || _runtimeArrays.ContainsKey(nameTok.Value) || _runtimeRecordTypes.ContainsKey(nameTok.Value) || _runtimeRecordInstances.ContainsKey(nameTok.Value) || _runtimeRecordArrays.ContainsKey(nameTok.Value) || _runtimeEnumTypes.ContainsKey(nameTok.Value) || _runtimeEnumInstances.ContainsKey(nameTok.Value) || _runtimeEnumArrays.ContainsKey(nameTok.Value))
                throw new CompileError("SEMANTIC", "S195", nameTok.Line, nameTok.Column, $"Runtime record type \"{nameTok.Value}\" conflicts with an existing symbol, array, record type, or record instance.");
            ExpectKeyword("with");

            var fields = new List<RuntimeRecordField>();
            var seen = new HashSet<string>(StringComparer.Ordinal);
            while (true)
            {
                ExpectWord("runtime", "P160", "Record fields use runtime int/bool/string/enum field declarations.");
                string fieldType;
                if (CurrentWordIs("enum"))
                {
                    ExpectWord("enum", "P160", "Expected enum record field type.");
                    fieldType = "enum";
                }
                else
                {
                    if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                        throw new CompileError("PARSE", "P160", Current.Line, Current.Column, "Record field type must be runtime int, bool, string, or enum.");
                    fieldType = Advance().Value;
                }
                ExpectWord("field", "P160", "Expected field after record field type.");
                var fieldTok = Expect("STRING", "record field name");
                if (fieldType == "enum")
                {
                    ExpectKeyword("from");
                    var enumTypeTok = Expect("STRING", "record enum field type name");
                    if (!_runtimeEnumTypes.ContainsKey(enumTypeTok.Value))
                        throw new CompileError("SEMANTIC", "S217", enumTypeTok.Line, enumTypeTok.Column, $"Runtime enum type \"{enumTypeTok.Value}\" is not defined.");
                    fieldType = "enum:" + enumTypeTok.Value;
                }
                if (!seen.Add(fieldTok.Value))
                    throw new CompileError("SEMANTIC", "S196", fieldTok.Line, fieldTok.Column, $"Duplicate field \"{fieldTok.Value}\" in record type \"{nameTok.Value}\".");
                fields.Add(new RuntimeRecordField(fieldTok.Value, fieldType));
                if (CurrentIs("COMMA"))
                {
                    Advance();
                    continue;
                }
                if (IsKeyword("and"))
                {
                    ExpectKeyword("and");
                    continue;
                }
                break;
            }
            ExpectLine();

            if (fields.Count == 0)
                throw new CompileError("SEMANTIC", "S196", nameTok.Line, nameTok.Column, $"Record type \"{nameTok.Value}\" must declare at least one field.");

            if (!apply)
                return;

            _runtimeRecordTypes[nameTok.Value] = new RuntimeRecordType(nameTok.Value, fields);
            _flow.Add($"RUNTIME_RECORD_TYPE|name={nameTok.Value}|fields={string.Join(",", fields.Select(f => f.Type + ":" + f.Name))}");
        }

        void ParseRuntimeRecordInstanceDefinitionStatement(bool apply, bool inIf)
        {
            ExpectKeyword("define");
            ExpectWord("runtime", "P161", "Expected runtime after define.");
            ExpectWord("record", "P161", "Expected record after define runtime.");
            var nameTok = Expect("STRING", "runtime record instance name");
            if (SymbolExists(nameTok.Value) || _runtimeArrays.ContainsKey(nameTok.Value) || _runtimeRecordTypes.ContainsKey(nameTok.Value) || _runtimeRecordInstances.ContainsKey(nameTok.Value) || _runtimeRecordArrays.ContainsKey(nameTok.Value) || _runtimeEnumTypes.ContainsKey(nameTok.Value) || _runtimeEnumInstances.ContainsKey(nameTok.Value) || _runtimeEnumArrays.ContainsKey(nameTok.Value))
                throw new CompileError("SEMANTIC", "S197", nameTok.Line, nameTok.Column, $"Runtime record \"{nameTok.Value}\" conflicts with an existing symbol, array, record type, or record instance.");
            ExpectKeyword("from");
            var typeTok = Expect("STRING", "runtime record type name");
            if (!_runtimeRecordTypes.TryGetValue(typeTok.Value, out var recordType))
                throw new CompileError("SEMANTIC", "S198", typeTok.Line, typeTok.Column, $"Runtime record type \"{typeTok.Value}\" is not defined.");
            ExpectLine();

            if (!apply)
                return;

            var instance = new RuntimeRecordInstance(nameTok.Value, recordType.Name, recordType.Fields);
            _runtimeRecordInstances[nameTok.Value] = instance;
            _flow.Add($"RUNTIME_RECORD|name={nameTok.Value}|type={recordType.Name}");
            foreach (var field in recordType.Fields)
                AddRuntimeAction(new RuntimeAction($"runtime_{RuntimeStorageActionType(field.Type)}_set", "", "static", RuntimeArrayDefaultValue(field.Type), RuntimeRecordFieldSlotName(instance, field.Name)));
        }

        (RuntimeRecordInstance Record, RuntimeRecordField Field, string Slot) RequireRuntimeRecordField(Token recordTok, Token fieldTok, string expectedType, string context)
        {
            var record = RequireRuntimeRecord(recordTok, context);
            var field = record.Fields.FirstOrDefault(f => f.Name == fieldTok.Value);
            if (field == null)
                throw new CompileError("SEMANTIC", "S200", fieldTok.Line, fieldTok.Column, $"{context} references unknown field \"{fieldTok.Value}\" on record \"{recordTok.Value}\".");
            if (field.Type != expectedType)
                throw new CompileError("SEMANTIC", "S201", fieldTok.Line, fieldTok.Column, $"{context} expects runtime {expectedType} field, but record field \"{recordTok.Value}.{fieldTok.Value}\" is runtime {field.Type}.");
            return (record, field, RuntimeRecordFieldSlotName(record, fieldTok.Value));
        }

        (RuntimeRecordInstance Record, RuntimeRecordField Field, string Slot) ParseRuntimeRecordFieldReadExpression(string declaredType, string context)
        {
            ExpectWord("runtime", "P162", "Expected runtime record field expression.");
            ExpectWord("record", "P162", "Expected record after runtime.");
            var recordTok = Expect("STRING", "runtime record instance name");
            ExpectWord("field", "P162", "Expected field after runtime record name.");
            var fieldTok = Expect("STRING", "runtime record field name");
            return RequireRuntimeRecordField(recordTok, fieldTok, declaredType, context);
        }

        void ParseRuntimeRecordFieldSetStatement(bool apply, bool inIf)
        {
            ExpectKeyword("set");
            ExpectWord("runtime", "P163", "Expected runtime after set.");
            ExpectWord("record", "P163", "Expected record after set runtime.");
            var recordTok = Expect("STRING", "runtime record instance name");
            ExpectWord("field", "P163", "Expected field after runtime record name.");
            var fieldTok = Expect("STRING", "runtime record field name");
            ExpectKeyword("to");

            var record = RequireRuntimeRecord(recordTok, "set runtime record");
            var field = record.Fields.FirstOrDefault(f => f.Name == fieldTok.Value);
            if (field == null)
                throw new CompileError("SEMANTIC", "S200", fieldTok.Line, fieldTok.Column, $"set runtime record references unknown field \"{fieldTok.Value}\" on record \"{recordTok.Value}\".");

            var value = ParseRuntimeTypedOperand(field.Type, $"set runtime record {field.Type} field");
            ExpectLine();

            if (!apply)
                return;

            AddRuntimeAction(new RuntimeAction($"runtime_{RuntimeStorageActionType(field.Type)}_set", "", value.Kind, value.Value, RuntimeRecordFieldSlotName(record, fieldTok.Value)));
        }

        void ParseRuntimeRecordArrayDefinitionStatement(bool apply, bool inIf)
        {
            ExpectKeyword("define");
            ExpectWord("runtime", "P166", "Expected runtime after define.");
            ExpectWord("record", "P166", "Expected record after define runtime.");
            ExpectWord("array", "P166", "Expected array after define runtime record.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "runtime record array name");
            if (SymbolExists(nameTok.Value) || _runtimeArrays.ContainsKey(nameTok.Value) || _runtimeRecordTypes.ContainsKey(nameTok.Value) || _runtimeRecordInstances.ContainsKey(nameTok.Value) || _runtimeRecordArrays.ContainsKey(nameTok.Value) || _runtimeEnumTypes.ContainsKey(nameTok.Value) || _runtimeEnumInstances.ContainsKey(nameTok.Value) || _runtimeEnumArrays.ContainsKey(nameTok.Value))
                throw new CompileError("SEMANTIC", "S206", nameTok.Line, nameTok.Column, $"Runtime record array \"{nameTok.Value}\" conflicts with an existing symbol, array, record type, record instance, or record array.");
            ExpectKeyword("from");
            var typeTok = Expect("STRING", "runtime record array type name");
            if (!_runtimeRecordTypes.TryGetValue(typeTok.Value, out var recordType))
                throw new CompileError("SEMANTIC", "S198", typeTok.Line, typeTok.Column, $"Runtime record type \"{typeTok.Value}\" is not defined.");
            ExpectWord("size", "P166", "Expected size after runtime record array type.");
            var sizeTok = Expect("INT", "runtime record array size");
            if (!int.TryParse(sizeTok.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var size))
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Runtime record array size must fit i32: {sizeTok.Value}.");
            if (size <= 0)
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, "Runtime record array size must be positive.");
            if (size > 512)
                throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, "Runtime record array size is capped at 512 in M54.");
            ExpectLine();

            if (!apply)
                return;

            var info = new RuntimeRecordArrayInfo(nameTok.Value, recordType.Name, recordType.Fields, size);
            _runtimeRecordArrays[nameTok.Value] = info;
            _flow.Add($"RUNTIME_RECORD_ARRAY|name={nameTok.Value}|type={recordType.Name}|size={size}");
            for (var i = 0; i < size; i++)
                foreach (var field in recordType.Fields)
                    AddRuntimeAction(new RuntimeAction($"runtime_{RuntimeStorageActionType(field.Type)}_set", "", "static", RuntimeArrayDefaultValue(field.Type), RuntimeRecordArrayFieldSlotName(info, i, field.Name)));
        }

        (RuntimeRecordArrayInfo Array, RuntimeRecordField Field, RuntimeArrayIndex Index, string SlotPrefix) ParseRuntimeRecordArrayFieldReadExpression(string declaredType, string context)
        {
            ExpectWord("runtime", "P167", "Expected runtime record array field expression.");
            ExpectWord("record", "P167", "Expected record after runtime.");
            ExpectWord("array", "P167", "Expected array after runtime record.");
            var arrayTok = Expect("STRING", "runtime record array name");
            var array = RequireRuntimeRecordArray(arrayTok, context);
            var index = ParseRuntimeRecordArrayIndex(array, context);
            ExpectWord("field", "P167", "Expected field after runtime record array index.");
            var fieldTok = Expect("STRING", "runtime record array field name");
            var field = array.Fields.FirstOrDefault(f => f.Name == fieldTok.Value);
            if (field == null)
                throw new CompileError("SEMANTIC", "S207", fieldTok.Line, fieldTok.Column, $"{context} references unknown field \"{fieldTok.Value}\" on record array \"{arrayTok.Value}\".");
            if (field.Type != declaredType)
                throw new CompileError("SEMANTIC", "S208", fieldTok.Line, fieldTok.Column, $"{context} expects runtime {declaredType} field, but record array field \"{arrayTok.Value}.{fieldTok.Value}\" is runtime {field.Type}.");
            return (array, field, index, RuntimeRecordArrayStorageName(array));
        }

        void ParseRuntimeRecordArrayFieldSetStatement(bool apply, bool inIf)
        {
            ExpectKeyword("set");
            ExpectWord("runtime", "P168", "Expected runtime after set.");
            ExpectWord("record", "P168", "Expected record after set runtime.");
            ExpectWord("array", "P168", "Expected array after set runtime record.");
            var arrayTok = Expect("STRING", "runtime record array name");
            var array = RequireRuntimeRecordArray(arrayTok, "set runtime record array");
            var index = ParseRuntimeRecordArrayIndex(array, "set runtime record array");
            ExpectWord("field", "P168", "Expected field after runtime record array index.");
            var fieldTok = Expect("STRING", "runtime record array field name");
            var field = array.Fields.FirstOrDefault(f => f.Name == fieldTok.Value);
            if (field == null)
                throw new CompileError("SEMANTIC", "S207", fieldTok.Line, fieldTok.Column, $"set runtime record array references unknown field \"{fieldTok.Value}\" on record array \"{arrayTok.Value}\".");
            ExpectKeyword("to");
            var value = ParseRuntimeTypedOperand(field.Type, $"set runtime record array {field.Type} field");
            ExpectLine();

            if (!apply)
                return;

            AddRuntimeRecordArrayBoundsCheckedDispatch(array, index, i =>
                AddRuntimeAction(new RuntimeAction($"runtime_{RuntimeStorageActionType(field.Type)}_set", "", value.Kind, value.Value, RuntimeRecordArrayFieldSlotName(array, i, field.Name))));
        }

        void ParseFunctionReturnStatement(bool apply, bool inIf)
        {
            var tok = Current;
            ExpectWord("return", "P140", "Expected return.");

            if (_currentRuntimeFunctionName == null || !CapturingRuntimeFunctionActions())
                throw new CompileError("SEMANTIC", "S159", tok.Line, tok.Column, "return is only supported inside function bodies.");

            if (CurrentIs("NEWLINE") || CurrentIs("EOF"))
            {
                ExpectLine();
                if (apply)
                {
                    RegisterRuntimeFunctionReturnType("void", tok);
                    AddRuntimeAction(new RuntimeAction("function_return", "", "static", "", ""));
                    _runtimeFunctionContainsReturn = true;
                }
                return;
            }

            string returnType;
            (string Kind, string Value) value;
            var returnActionType = "";

            if (CurrentWordIs("runtime"))
            {
                ExpectWord("runtime", "P141", "Expected runtime in return value.");
                if (CurrentWordIs("enum"))
                {
                    ExpectWord("enum", "P185", "Expected enum after runtime in return value.");
                    var enumTok = Expect("STRING", "return runtime enum source name");
                    var source = RequireRuntimeEnum(enumTok, "return runtime enum");
                    returnType = "enum:" + source.TypeName;
                    value = ("slot", RuntimeEnumStorageName(source));
                    returnActionType = "int";
                }
                else
                {
                    if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                        throw new CompileError("PARSE", "P141", Current.Line, Current.Column, "Expected runtime return type: int, bool, string, or enum.");
                    returnType = Advance().Value;
                    value = returnType switch
                    {
                        "int" => ParseRuntimeIntOperand("return runtime int"),
                        "bool" => ParseRuntimeBoolOperand("return runtime bool"),
                        "string" => ParseRuntimeStringOperand("return runtime string"),
                        _ => throw new CompileError("PARSE", "P141", Current.Line, Current.Column, "Unsupported runtime return type.")
                    };
                    returnActionType = returnType;
                }
            }
            else if (CurrentWordIs("enum"))
            {
                ExpectWord("enum", "P185", "Expected enum return literal.");
                var valueTok = Expect("STRING", "return enum value name");
                ExpectKeyword("from");
                var typeTok = Expect("STRING", "return enum type name");
                if (!_runtimeEnumTypes.TryGetValue(typeTok.Value, out var enumType))
                    throw new CompileError("SEMANTIC", "S217", typeTok.Line, typeTok.Column, $"Runtime enum type \"{typeTok.Value}\" is not defined.");
                var index = RuntimeEnumValueIndex(enumType, valueTok, "return enum");
                returnType = "enum:" + enumType.Name;
                value = ("static", index.ToString(CultureInfo.InvariantCulture));
                returnActionType = "int";
            }
            else if (IsKeyword("int"))
            {
                ExpectKeyword("int");
                returnType = "int";
                value = ParseRuntimeIntOperand("return int");
                returnActionType = "int";
            }
            else if (IsKeyword("bool"))
            {
                ExpectKeyword("bool");
                returnType = "bool";
                value = ParseRuntimeBoolOperand("return bool");
                returnActionType = "bool";
            }
            else if (IsKeyword("string"))
            {
                ExpectKeyword("string");
                returnType = "string";
                var valueTok = Expect("STRING", "return string literal");
                value = ("static", valueTok.Value);
                returnActionType = "string";
            }
            else
            {
                throw new CompileError("SEMANTIC", "S160", Current.Line, Current.Column, "return values require int, bool, string, enum, runtime <type>, or runtime enum in M59.");
            }

            ExpectLine();

            if (apply)
            {
                RegisterRuntimeFunctionReturnType(returnType, tok);
                AddRuntimeAction(new RuntimeAction("function_return_" + returnActionType, "", value.Kind, value.Value, ""));
                _runtimeFunctionContainsReturn = true;
            }
        }

        void RegisterRuntimeFunctionReturnType(string returnType, Token token)
        {
            if (_currentRuntimeFunctionReturnType == null)
            {
                _currentRuntimeFunctionReturnType = returnType;
                return;
            }

            if (_currentRuntimeFunctionReturnType != returnType)
                throw new CompileError("SEMANTIC", "S161", token.Line, token.Column, $"Function \"{_currentRuntimeFunctionName}\" mixes return types: {_currentRuntimeFunctionReturnType} and {returnType}.");
        }

        VarInfo RequireRuntimeIntSymbol(Token token, string code, string context)
        {
            var info = ResolveSymbol(token, "S131", name => $"Unknown runtime int symbol \"{name}\".");
            if (!info.IsRuntime || info.Type != "int")
                throw new CompileError("SEMANTIC", code, token.Line, token.Column, $"{context} \"{token.Value}\" must be a runtime int slot.");
            return info;
        }

        VarInfo RequireRuntimeBoolSymbol(Token token, string code, string context)
        {
            var info = ResolveSymbol(token, "S131", name => $"Unknown runtime bool symbol \"{name}\".");
            if (!info.IsRuntime || info.Type != "bool")
                throw new CompileError("SEMANTIC", code, token.Line, token.Column, $"{context} \"{token.Value}\" must be a runtime bool slot.");
            return info;
        }

        VarInfo RequireRuntimeStringSymbol(Token token, string code, string context)
        {
            var info = ResolveSymbol(token, "S131", name => $"Unknown runtime string symbol \"{name}\".");
            if (!info.IsRuntime || info.Type != "text")
                throw new CompileError("SEMANTIC", code, token.Line, token.Column, $"{context} \"{token.Value}\" must be a runtime string slot.");
            return info;
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

        List<RuntimeAction> ActiveRuntimeActions() => _runtimeActionCapture ?? _runtimeActions;

        bool CapturingRuntimeFunctionActions() => _runtimeActionCapture != null;

        void AddRuntimeAction(RuntimeAction action)
        {
            if (!CapturingRuntimeFunctionActions())
                FlushPendingStaticPrintsToRuntime();
            ActiveRuntimeActions().Add(action);
        }

        void FlushPendingStaticPrintsToRuntime()
        {
            if (_prints.Count == 0)
                return;

            var text = string.Join("\n", _prints);
            _prints.Clear();
            if (!CapturingRuntimeFunctionActions())
            {
                _message = null;
                _messageExpr = "";
                _messageCommand = "";
            }
            ActiveRuntimeActions().Add(new RuntimeAction("print_stdout", "", "static", text, ""));
        }

        void AppendPrint(ExprResult printed)
        {
            var formatted = FormatValue(printed);
            if (_runtimeActions.Count > 0 || CapturingRuntimeFunctionActions())
            {
                AddRuntimeAction(new RuntimeAction("print_stdout", "", "static", formatted, ""));
                return;
            }

            _prints.Add(formatted);
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
               (_runtimeSymbols.Contains(_tokens[_pos + 1].Value) || _runtimeParamAliases.ContainsKey(_tokens[_pos + 1].Value));

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
                AddRuntimeAction(new RuntimeAction("file_write", pathTok.Value, value.Kind, value.Value, ""));
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
                AddRuntimeAction(new RuntimeAction("file_append", pathTok.Value, value.Kind, value.Value, ""));
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
            AddRuntimeAction(new RuntimeAction("file_load", pathTok.Value, "slot", RuntimeSlotName(targetTok), RuntimeSlotName(targetTok)));
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

                if (apply) AddRuntimeAction(new RuntimeAction("event_window_closed", "", "static", "", nameTok.Value));

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

                if (apply) AddRuntimeAction(new RuntimeAction("event_end", "", "static", "", nameTok.Value));
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

                if (apply) AddRuntimeAction(new RuntimeAction("event_key_pressed", "", "static", keyTok.Value, ""));

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

                if (apply) AddRuntimeAction(new RuntimeAction("event_end", "", "static", keyTok.Value, ""));
            }
            else
            {
                ParseUiEventStatementAfterWhen(apply, inIf);
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
            if (CapturingRuntimeFunctionActions())
                throw new CompileError("SEMANTIC", "S052", Current.Line, Current.Column, "Nested function definitions are not supported in M39.");

            ExpectKeyword("define");
            if (IsKeyword("const"))
                throw new CompileError("SEMANTIC", "S048", Current.Line, Current.Column, "const function is not supported.");
            ExpectKeyword("function");
            if (!IsKeyword("called"))
                throw new CompileError("PARSE", "P090", Current.Line, Current.Column, "Expected keyword \"called\" after define function.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "function name");
            if (_functions.ContainsKey(nameTok.Value) || _runtimeFunctionMap.ContainsKey(nameTok.Value))
                throw new CompileError("SEMANTIC", "S049", nameTok.Line, nameTok.Column, $"Function \"{nameTok.Value}\" is already defined.");
            var parameters = ParseFunctionParameterList(nameTok);
            ExpectLine();
            var body = ReadBlock("function", "P092", "Expected end function.");
            _functions[nameTok.Value] = body;
            _runtimeFunctionMap[nameTok.Value] = new RuntimeFunction(nameTok.Value, new List<RuntimeAction>(), "void", parameters);

            var actions = new List<RuntimeAction>();
            var locals = new List<RuntimeLocal>();
            var savedCapture = _runtimeActionCapture;
            var savedFunctionName = _currentRuntimeFunctionName;
            var savedFunctionContainsReturn = _runtimeFunctionContainsReturn;
            var savedFunctionReturnType = _currentRuntimeFunctionReturnType;
            var savedFunctionLocals = _currentRuntimeFunctionLocals;
            var savedLocalSymbols = _runtimeFunctionSavedLocalSymbols;
            var savedLocalArrays = _runtimeFunctionSavedLocalArrays;
            var savedLocalRecords = _runtimeFunctionSavedLocalRecords;
            var savedLocalEnums = _runtimeFunctionSavedLocalEnums;
            var savedLocalEnumArrays = _runtimeFunctionSavedLocalEnumArrays;
            var savedParamAliases = new Dictionary<string, string>(_runtimeParamAliases, StringComparer.Ordinal);
            var savedParamNames = new HashSet<string>(_runtimeFunctionParamNames, StringComparer.Ordinal);
            var savedLocalNames = new HashSet<string>(_runtimeFunctionLocalNames, StringComparer.Ordinal);
            var savedParamSymbols = new Dictionary<string, VarInfo>(StringComparer.Ordinal);
            var functionSavedLocalSymbols = new Dictionary<string, VarInfo>(StringComparer.Ordinal);
            var functionSavedLocalArrays = new Dictionary<string, RuntimeArrayInfo>(StringComparer.Ordinal);
            var functionSavedLocalRecords = new Dictionary<string, RuntimeRecordInstance>(StringComparer.Ordinal);
            var functionSavedLocalEnums = new Dictionary<string, RuntimeEnumInstance>(StringComparer.Ordinal);
            var functionSavedLocalEnumArrays = new Dictionary<string, RuntimeEnumArrayInfo>(StringComparer.Ordinal);
            _runtimeActionCapture = actions;
            _currentRuntimeFunctionName = nameTok.Value;
            _runtimeFunctionContainsReturn = false;
            _currentRuntimeFunctionReturnType = null;
            _currentRuntimeFunctionLocals = locals;
            _runtimeFunctionSavedLocalSymbols = functionSavedLocalSymbols;
            _runtimeFunctionSavedLocalArrays = functionSavedLocalArrays;
            _runtimeFunctionSavedLocalRecords = functionSavedLocalRecords;
            _runtimeFunctionSavedLocalEnums = functionSavedLocalEnums;
            _runtimeFunctionSavedLocalEnumArrays = functionSavedLocalEnumArrays;
            _runtimeFunctionParamNames.Clear();
            _runtimeFunctionLocalNames.Clear();
            foreach (var param in parameters)
                _runtimeFunctionParamNames.Add(param.Name);
            try
            {
                foreach (var param in parameters)
                {
                    if (IsRuntimeEnumArrayParamType(param.Type))
                    {
                        SaveRuntimeEnumArrayForFunctionScope(param.Name);
                        var typeName = RuntimeEnumArrayTypeNameFromParam(param.Type);
                        if (!_runtimeEnumTypes.ContainsKey(typeName))
                            throw new CompileError("SEMANTIC", "S217", nameTok.Line, nameTok.Column, $"Runtime enum type \"{typeName}\" is not defined.");
                        _runtimeEnumArrays[param.Name] = new RuntimeEnumArrayInfo(param.Name, typeName, param.Size, param.Slot);
                        continue;
                    }
                    if (IsRuntimeArrayType(param.Type))
                    {
                        SaveRuntimeArrayForFunctionScope(param.Name);
                        _runtimeArrays[param.Name] = new RuntimeArrayInfo(param.Name, RuntimeArrayElementType(param.Type), param.Size, param.Slot);
                        continue;
                    }
                    if (IsRuntimeRecordParamType(param.Type))
                    {
                        SaveRuntimeRecordForFunctionScope(param.Name);
                        var typeName = RuntimeRecordTypeNameFromParam(param.Type);
                        if (!_runtimeRecordTypes.TryGetValue(typeName, out var recordType))
                            throw new CompileError("SEMANTIC", "S198", nameTok.Line, nameTok.Column, $"Runtime record type \"{typeName}\" is not defined.");
                        _runtimeRecordInstances[param.Name] = new RuntimeRecordInstance(param.Name, recordType.Name, recordType.Fields, param.Slot);
                        continue;
                    }
                    if (IsRuntimeEnumParamType(param.Type))
                    {
                        SaveRuntimeEnumForFunctionScope(param.Name);
                        var typeName = RuntimeEnumTypeNameFromParam(param.Type);
                        if (!_runtimeEnumTypes.ContainsKey(typeName))
                            throw new CompileError("SEMANTIC", "S217", nameTok.Line, nameTok.Column, $"Runtime enum type \"{typeName}\" is not defined.");
                        _runtimeEnumInstances[param.Name] = new RuntimeEnumInstance(param.Name, typeName, param.Slot);
                        continue;
                    }

                    if (_vars.TryGetValue(param.Name, out var existing))
                        savedParamSymbols[param.Name] = existing;
                    _runtimeParamAliases[param.Name] = param.Slot;
                    _vars[param.Name] = new VarInfo(RuntimeTypeToSymbolType(param.Type), param.Slot, IsRuntime: true);
                }

                RunTokenBlock(body);
                if (!_runtimeFunctionContainsReturn)
                    FlushPendingStaticPrintsToRuntime();
            }
            finally
            {
                foreach (var local in locals)
                {
                    if (IsRuntimeEnumArrayParamType(local.Type))
                    {
                        if (functionSavedLocalEnumArrays.TryGetValue(local.Name, out var savedEnumArray))
                            _runtimeEnumArrays[local.Name] = savedEnumArray;
                        else
                            _runtimeEnumArrays.Remove(local.Name);
                        continue;
                    }
                    if (IsRuntimeArrayType(local.Type))
                    {
                        if (functionSavedLocalArrays.TryGetValue(local.Name, out var savedArray))
                            _runtimeArrays[local.Name] = savedArray;
                        else
                            _runtimeArrays.Remove(local.Name);
                        continue;
                    }
                    if (IsRuntimeRecordParamType(local.Type))
                    {
                        if (functionSavedLocalRecords.TryGetValue(local.Name, out var savedRecord))
                            _runtimeRecordInstances[local.Name] = savedRecord;
                        else
                            _runtimeRecordInstances.Remove(local.Name);
                        continue;
                    }
                    if (IsRuntimeEnumParamType(local.Type))
                    {
                        if (functionSavedLocalEnums.TryGetValue(local.Name, out var savedEnum))
                            _runtimeEnumInstances[local.Name] = savedEnum;
                        else
                            _runtimeEnumInstances.Remove(local.Name);
                        continue;
                    }

                    if (functionSavedLocalSymbols.TryGetValue(local.Name, out var savedSymbol))
                        _vars[local.Name] = savedSymbol;
                    else
                        _vars.Remove(local.Name);
                }
                foreach (var param in parameters)
                {
                    if (IsRuntimeEnumArrayParamType(param.Type))
                    {
                        if (functionSavedLocalEnumArrays.TryGetValue(param.Name, out var savedEnumArray))
                            _runtimeEnumArrays[param.Name] = savedEnumArray;
                        else
                            _runtimeEnumArrays.Remove(param.Name);
                        continue;
                    }
                    if (IsRuntimeArrayType(param.Type))
                    {
                        if (functionSavedLocalArrays.TryGetValue(param.Name, out var savedArray))
                            _runtimeArrays[param.Name] = savedArray;
                        else
                            _runtimeArrays.Remove(param.Name);
                        continue;
                    }
                    if (IsRuntimeRecordParamType(param.Type))
                    {
                        if (functionSavedLocalRecords.TryGetValue(param.Name, out var savedRecord))
                            _runtimeRecordInstances[param.Name] = savedRecord;
                        else
                            _runtimeRecordInstances.Remove(param.Name);
                        continue;
                    }
                    if (IsRuntimeEnumParamType(param.Type))
                    {
                        if (functionSavedLocalEnums.TryGetValue(param.Name, out var savedEnum))
                            _runtimeEnumInstances[param.Name] = savedEnum;
                        else
                            _runtimeEnumInstances.Remove(param.Name);
                        continue;
                    }

                    if (savedParamSymbols.TryGetValue(param.Name, out var savedSymbol))
                        _vars[param.Name] = savedSymbol;
                    else
                        _vars.Remove(param.Name);
                }
                _runtimeParamAliases.Clear();
                foreach (var kvp in savedParamAliases)
                    _runtimeParamAliases[kvp.Key] = kvp.Value;
                _runtimeFunctionParamNames.Clear();
                foreach (var name in savedParamNames)
                    _runtimeFunctionParamNames.Add(name);
                _runtimeFunctionLocalNames.Clear();
                foreach (var name in savedLocalNames)
                    _runtimeFunctionLocalNames.Add(name);
                _runtimeActionCapture = savedCapture;
                _currentRuntimeFunctionName = savedFunctionName;
                _runtimeFunctionContainsReturn = savedFunctionContainsReturn;
                _currentRuntimeFunctionLocals = savedFunctionLocals;
                _runtimeFunctionSavedLocalSymbols = savedLocalSymbols;
                _runtimeFunctionSavedLocalArrays = savedLocalArrays;
                _runtimeFunctionSavedLocalRecords = savedLocalRecords;
                _runtimeFunctionSavedLocalEnums = savedLocalEnums;
                _runtimeFunctionSavedLocalEnumArrays = savedLocalEnumArrays;
            }

            var functionReturnType = _currentRuntimeFunctionReturnType ?? "void";
            _currentRuntimeFunctionReturnType = savedFunctionReturnType;

            var fn = new RuntimeFunction(nameTok.Value, actions, functionReturnType, parameters, locals);
            _runtimeFunctionMap[nameTok.Value] = fn;
            _runtimeFunctions.Add(fn);
        }

        List<RuntimeParam> ParseFunctionParameterList(Token functionNameTok)
        {
            var parameters = new List<RuntimeParam>();
            if (!IsKeyword("with"))
                return parameters;

            ExpectKeyword("with");
            var seen = new HashSet<string>(StringComparer.Ordinal);
            while (true)
            {
                ExpectWord("runtime", "P142", "Function parameters use runtime int/bool/string slots, runtime arrays, runtime records, and runtime enums.");

                string type;
                var isArrayParam = false;
                var isRecordParam = false;
                var size = 0;

                if (CurrentWordIs("record"))
                {
                    ExpectWord("record", "P169", "Expected record after runtime for record parameter.");
                    var nameTok = Expect("STRING", "runtime record parameter name");
                    ExpectKeyword("from");
                    var typeTok = Expect("STRING", "runtime record parameter type");
                    if (!_runtimeRecordTypes.ContainsKey(typeTok.Value))
                        throw new CompileError("SEMANTIC", "S198", typeTok.Line, typeTok.Column, $"Runtime record type \"{typeTok.Value}\" is not defined.");
                    type = "record:" + typeTok.Value;
                    isRecordParam = true;

                    if (!seen.Add(nameTok.Value))
                        throw new CompileError("SEMANTIC", "S164", nameTok.Line, nameTok.Column, $"Function \"{functionNameTok.Value}\" has duplicate parameter \"{nameTok.Value}\".");
                    if (SymbolExists(nameTok.Value) || _runtimeArrays.ContainsKey(nameTok.Value) || _runtimeRecordInstances.ContainsKey(nameTok.Value) || _runtimeRecordArrays.ContainsKey(nameTok.Value) || _runtimeEnumTypes.ContainsKey(nameTok.Value) || _runtimeEnumInstances.ContainsKey(nameTok.Value) || _runtimeEnumArrays.ContainsKey(nameTok.Value))
                        throw new CompileError("SEMANTIC", "S165", nameTok.Line, nameTok.Column, $"Function parameter \"{nameTok.Value}\" conflicts with an existing symbol; M42/M53/M59 does not support parameter shadowing.");

                    parameters.Add(new RuntimeParam(nameTok.Value, type, RuntimeParamRecordSlotName(functionNameTok.Value, nameTok.Value)));
                }
                else if (CurrentWordIs("enum"))
                {
                    ExpectWord("enum", "P186", "Expected enum after runtime for enum parameter.");
                    if (CurrentWordIs("array"))
                    {
                        ExpectWord("array", "P190", "Expected array after runtime enum for enum array parameter.");
                        var nameTok = Expect("STRING", "runtime enum array parameter name");
                        ExpectKeyword("from");
                        var typeTok = Expect("STRING", "runtime enum array parameter type");
                        if (!_runtimeEnumTypes.ContainsKey(typeTok.Value))
                            throw new CompileError("SEMANTIC", "S217", typeTok.Line, typeTok.Column, $"Runtime enum type \"{typeTok.Value}\" is not defined.");
                        type = "enum_array:" + typeTok.Value;
                        ExpectWord("size", "P190", "Expected size after runtime enum array parameter type.");
                        var sizeTok = Expect("INT", "runtime enum array parameter size");
                        if (!int.TryParse(sizeTok.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out size))
                            throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Runtime enum array parameter size must fit i32: {sizeTok.Value}.");
                        if (size <= 0)
                            throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, "Runtime enum array parameter size must be positive.");
                        if (size > 1024)
                            throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, "Runtime enum array parameter size is capped at 1024 in M62.");

                        if (!seen.Add(nameTok.Value))
                            throw new CompileError("SEMANTIC", "S164", nameTok.Line, nameTok.Column, $"Function \"{functionNameTok.Value}\" has duplicate parameter \"{nameTok.Value}\".");
                        if (SymbolExists(nameTok.Value) || _runtimeArrays.ContainsKey(nameTok.Value) || _runtimeRecordInstances.ContainsKey(nameTok.Value) || _runtimeRecordArrays.ContainsKey(nameTok.Value) || _runtimeEnumTypes.ContainsKey(nameTok.Value) || _runtimeEnumInstances.ContainsKey(nameTok.Value) || _runtimeEnumArrays.ContainsKey(nameTok.Value))
                            throw new CompileError("SEMANTIC", "S165", nameTok.Line, nameTok.Column, $"Function parameter \"{nameTok.Value}\" conflicts with an existing symbol; M62 does not support parameter shadowing.");

                        parameters.Add(new RuntimeParam(nameTok.Value, type, RuntimeParamArraySlotName(functionNameTok.Value, nameTok.Value), size));
                    }
                    else
                    {
                        var nameTok = Expect("STRING", "runtime enum parameter name");
                        ExpectKeyword("from");
                        var typeTok = Expect("STRING", "runtime enum parameter type");
                        if (!_runtimeEnumTypes.ContainsKey(typeTok.Value))
                            throw new CompileError("SEMANTIC", "S217", typeTok.Line, typeTok.Column, $"Runtime enum type \"{typeTok.Value}\" is not defined.");
                        type = "enum:" + typeTok.Value;

                        if (!seen.Add(nameTok.Value))
                            throw new CompileError("SEMANTIC", "S164", nameTok.Line, nameTok.Column, $"Function \"{functionNameTok.Value}\" has duplicate parameter \"{nameTok.Value}\".");
                        if (SymbolExists(nameTok.Value) || _runtimeArrays.ContainsKey(nameTok.Value) || _runtimeRecordInstances.ContainsKey(nameTok.Value) || _runtimeRecordArrays.ContainsKey(nameTok.Value) || _runtimeEnumTypes.ContainsKey(nameTok.Value) || _runtimeEnumInstances.ContainsKey(nameTok.Value) || _runtimeEnumArrays.ContainsKey(nameTok.Value))
                            throw new CompileError("SEMANTIC", "S165", nameTok.Line, nameTok.Column, $"Function parameter \"{nameTok.Value}\" conflicts with an existing symbol; M59 does not support parameter shadowing.");

                        parameters.Add(new RuntimeParam(nameTok.Value, type, RuntimeParamSlotName(functionNameTok.Value, nameTok.Value)));
                    }
                }
                else
                {
                    if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                        throw new CompileError("PARSE", "P142", Current.Line, Current.Column, "Expected function parameter type: runtime int, runtime bool, runtime string, runtime enum, runtime <type> array, or runtime record.");
                    type = Advance().Value;
                    if (CurrentWordIs("array"))
                    {
                        ExpectWord("array", "P156", $"Expected array after runtime {type} parameter type.");
                        isArrayParam = true;
                    }
                    var nameTok = Expect("STRING", "function parameter name");
                    if (isArrayParam)
                    {
                        ExpectWord("size", "P156", $"Expected size after runtime {type} array parameter name.");
                        var sizeTok = Expect("INT", $"runtime {type} array parameter size");
                        if (!int.TryParse(sizeTok.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out size))
                            throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Runtime {type} array parameter size must fit i32: {sizeTok.Value}.");
                        if (size <= 0)
                            throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Runtime {type} array parameter size must be positive.");
                        if (size > 1024)
                            throw new CompileError("SEMANTIC", "S180", sizeTok.Line, sizeTok.Column, $"Runtime {type} array parameter size is capped at 1024 in M50.");
                    }
                    if (!seen.Add(nameTok.Value))
                        throw new CompileError("SEMANTIC", "S164", nameTok.Line, nameTok.Column, $"Function \"{functionNameTok.Value}\" has duplicate parameter \"{nameTok.Value}\".");
                    if (SymbolExists(nameTok.Value) || _runtimeArrays.ContainsKey(nameTok.Value) || _runtimeRecordInstances.ContainsKey(nameTok.Value) || _runtimeRecordArrays.ContainsKey(nameTok.Value) || _runtimeEnumTypes.ContainsKey(nameTok.Value) || _runtimeEnumInstances.ContainsKey(nameTok.Value) || _runtimeEnumArrays.ContainsKey(nameTok.Value))
                        throw new CompileError("SEMANTIC", "S165", nameTok.Line, nameTok.Column, $"Function parameter \"{nameTok.Value}\" conflicts with an existing symbol; M42/M53/M59 does not support parameter shadowing.");

                    if (isArrayParam)
                        parameters.Add(new RuntimeParam(nameTok.Value, type + "_array", RuntimeParamArraySlotName(functionNameTok.Value, nameTok.Value), size));
                    else
                        parameters.Add(new RuntimeParam(nameTok.Value, type, RuntimeParamSlotName(functionNameTok.Value, nameTok.Value)));
                }

                _ = isRecordParam;
                if (CurrentIs("COMMA"))
                {
                    Advance();
                    continue;
                }
                if (IsKeyword("and"))
                {
                    ExpectKeyword("and");
                    continue;
                }
                break;
            }

            return parameters;
        }

        FunctionCallExpression ParseFunctionCallExpression()
        {
            ExpectKeyword("call");
            if (!IsKeyword("function"))
                throw new CompileError("PARSE", "P093", Current.Line, Current.Column, "Expected keyword \"function\" after call.");
            ExpectKeyword("function");
            var nameTok = Expect("STRING", "function name");

            if (_currentRuntimeFunctionName == nameTok.Value || _callStack.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S051", nameTok.Line, nameTok.Column, $"Recursive function call \"{nameTok.Value}\" is not supported.");

            var args = ParseFunctionCallArguments();
            return new FunctionCallExpression(nameTok, nameTok.Value, args);
        }

        string ParseFunctionCallExpressionName()
            => ParseFunctionCallExpression().Name;

        List<RuntimeArgument> ParseFunctionCallArguments()
        {
            var args = new List<RuntimeArgument>();
            if (!IsKeyword("with"))
                return args;

            ExpectKeyword("with");
            while (true)
            {
                args.Add(ParseFunctionCallArgument());
                if (CurrentIs("COMMA"))
                {
                    Advance();
                    continue;
                }
                if (IsKeyword("and"))
                {
                    ExpectKeyword("and");
                    continue;
                }
                break;
            }
            return args;
        }

        RuntimeArgument ParseFunctionCallArgument()
        {
            if (CurrentWordIs("runtime"))
            {
                ExpectWord("runtime", "P143", "Expected runtime function argument.");
                if (CurrentWordIs("record"))
                {
                    ExpectWord("record", "P170", "Expected record after runtime for record argument.");
                    var recordTok = Expect("STRING", "runtime record argument name");
                    var record = RequireRuntimeRecord(recordTok, "function runtime record argument");
                    return new RuntimeArgument("record:" + record.TypeName, "record", RuntimeRecordStorageName(record));
                }

                if (CurrentWordIs("enum"))
                {
                    ExpectWord("enum", "P187", "Expected enum after runtime for enum argument.");
                    if (CurrentWordIs("array"))
                    {
                        ExpectWord("array", "P191", "Expected array after runtime enum for enum array argument.");
                        var arrayTok = Expect("STRING", "runtime enum array argument name");
                        var array = RequireRuntimeEnumArray(arrayTok, "function runtime enum array argument");
                        return new RuntimeArgument("enum_array:" + array.TypeName, "enum_array", RuntimeEnumArrayStorageName(array), array.Size);
                    }
                    var enumTok = Expect("STRING", "runtime enum argument name");
                    var instance = RequireRuntimeEnum(enumTok, "function runtime enum argument");
                    return new RuntimeArgument("enum:" + instance.TypeName, "slot", RuntimeEnumStorageName(instance));
                }

                if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                    throw new CompileError("PARSE", "P143", Current.Line, Current.Column, "Expected runtime argument type: int, bool, string, enum, <type> array, or record.");
                var type = Advance().Value;
                if (CurrentWordIs("array"))
                {
                    ExpectWord("array", "P157", $"Expected array after runtime {type} argument type.");
                    var arrayTok = Expect("STRING", $"runtime {type} array argument name");
                    var array = RequireRuntimeArray(arrayTok, type, "S184", "function runtime array argument");
                    return new RuntimeArgument(type + "_array", "array", RuntimeArrayStorageName(array), array.Size);
                }

                var operand = type switch
                {
                    "int" => ParseRuntimeIntOperand("function runtime int argument"),
                    "bool" => ParseRuntimeBoolOperand("function runtime bool argument"),
                    "string" => ParseRuntimeStringOperand("function runtime string argument"),
                    _ => throw new CompileError("PARSE", "P143", Current.Line, Current.Column, "Unsupported runtime function argument type.")
                };
                if (operand.Kind != "slot")
                    throw new CompileError("SEMANTIC", "S166", Current.Line, Current.Column, "runtime function arguments must reference runtime slots.");
                return new RuntimeArgument(type, operand.Kind, operand.Value);
            }

            if (IsKeyword("int"))
            {
                ExpectKeyword("int");
                var value = ParseRuntimeIntOperand("function int argument");
                if (value.Kind != "static")
                    throw new CompileError("SEMANTIC", "S167", Current.Line, Current.Column, "int function arguments use int literals; use runtime int for slot arguments.");
                return new RuntimeArgument("int", value.Kind, value.Value);
            }
            if (IsKeyword("bool"))
            {
                ExpectKeyword("bool");
                var value = ParseRuntimeBoolOperand("function bool argument");
                if (value.Kind != "static")
                    throw new CompileError("SEMANTIC", "S167", Current.Line, Current.Column, "bool function arguments use bool literals; use runtime bool for slot arguments.");
                return new RuntimeArgument("bool", value.Kind, value.Value);
            }
            if (IsKeyword("string"))
            {
                var value = ParseRuntimeStringStaticLiteral("function string argument");
                return new RuntimeArgument("string", value.Kind, value.Value);
            }

            throw new CompileError("PARSE", "P143", Current.Line, Current.Column, "Function arguments require int, bool, string, runtime <type>, runtime enum, runtime <type> array, or runtime record.");
        }

        void AddFunctionArgumentSetupActions(RuntimeFunction fn, List<RuntimeArgument> args, Token callToken)
        {
            var parameters = fn.Params ?? new List<RuntimeParam>();
            if (args.Count != parameters.Count)
                throw new CompileError("SEMANTIC", "S168", callToken.Line, callToken.Column, $"Function \"{fn.Name}\" expects {parameters.Count} argument(s), but got {args.Count}.");

            for (var i = 0; i < parameters.Count; i++)
            {
                var param = parameters[i];
                var arg = args[i];
                if (arg.Type != param.Type)
                    throw new CompileError("SEMANTIC", "S169", callToken.Line, callToken.Column, $"Function \"{fn.Name}\" parameter \"{param.Name}\" expects {param.Type}, but got {arg.Type}.");

                if (IsRuntimeEnumArrayParamType(param.Type))
                {
                    if (arg.Size != param.Size)
                        throw new CompileError("SEMANTIC", "S232", callToken.Line, callToken.Column, $"Function \"{fn.Name}\" enum array parameter \"{param.Name}\" expects size {param.Size}, but got size {arg.Size}.");
                    for (var element = 0; element < param.Size; element++)
                    {
                        AddRuntimeAction(new RuntimeAction(
                            "runtime_int_set",
                            "",
                            "slot",
                            RuntimeEnumArrayElementSlotName(arg.Value, element),
                            RuntimeEnumArrayElementSlotName(param.Slot, element)));
                    }
                    continue;
                }
                if (IsRuntimeArrayType(param.Type))
                {
                    if (arg.Size != param.Size)
                        throw new CompileError("SEMANTIC", "S191", callToken.Line, callToken.Column, $"Function \"{fn.Name}\" array parameter \"{param.Name}\" expects size {param.Size}, but got size {arg.Size}.");
                    var elementType = RuntimeArrayElementType(param.Type);
                    for (var element = 0; element < param.Size; element++)
                    {
                        AddRuntimeAction(new RuntimeAction(
                            $"runtime_{elementType}_set",
                            "",
                            "slot",
                            RuntimeArrayElementSlotName(arg.Value, elementType, element),
                            RuntimeArrayElementSlotName(param.Slot, elementType, element)));
                    }
                    continue;
                }
                if (IsRuntimeRecordParamType(param.Type))
                {
                    var typeName = RuntimeRecordTypeNameFromParam(param.Type);
                    if (!_runtimeRecordTypes.TryGetValue(typeName, out var recordType))
                        throw new CompileError("SEMANTIC", "S198", callToken.Line, callToken.Column, $"Runtime record type \"{typeName}\" is not defined.");
                    foreach (var field in recordType.Fields)
                    {
                        AddRuntimeAction(new RuntimeAction(
                            $"runtime_{RuntimeStorageActionType(field.Type)}_set",
                            "",
                            "slot",
                            RuntimeRecordFieldSlotName(arg.Value, field.Name),
                            RuntimeRecordFieldSlotName(param.Slot, field.Name)));
                    }
                    continue;
                }
                if (IsRuntimeEnumParamType(param.Type))
                {
                    AddRuntimeAction(new RuntimeAction("runtime_int_set", "", arg.Kind, arg.Value, param.Slot));
                    continue;
                }

                AddRuntimeAction(new RuntimeAction($"runtime_{param.Type}_set", "", arg.Kind, arg.Value, param.Slot));
            }
        }

        void AddFunctionArgumentCopyBackActions(RuntimeFunction fn, List<RuntimeArgument> args, Token callToken)
        {
            var parameters = fn.Params ?? new List<RuntimeParam>();
            for (var i = 0; i < parameters.Count; i++)
            {
                var param = parameters[i];
                var arg = args[i];
                if (IsRuntimeEnumArrayParamType(param.Type))
                {
                    if (arg.Type != param.Type || arg.Size != param.Size)
                        continue;
                    for (var element = 0; element < param.Size; element++)
                    {
                        AddRuntimeAction(new RuntimeAction(
                            "runtime_int_set",
                            "",
                            "slot",
                            RuntimeEnumArrayElementSlotName(param.Slot, element),
                            RuntimeEnumArrayElementSlotName(arg.Value, element)));
                    }
                    continue;
                }
                if (IsRuntimeArrayType(param.Type))
                {
                    if (arg.Type != param.Type || arg.Size != param.Size)
                        continue;
                    var elementType = RuntimeArrayElementType(param.Type);
                    for (var element = 0; element < param.Size; element++)
                    {
                        AddRuntimeAction(new RuntimeAction(
                            $"runtime_{elementType}_set",
                            "",
                            "slot",
                            RuntimeArrayElementSlotName(param.Slot, elementType, element),
                            RuntimeArrayElementSlotName(arg.Value, elementType, element)));
                    }
                    continue;
                }
                if (IsRuntimeRecordParamType(param.Type))
                {
                    if (arg.Type != param.Type)
                        continue;
                    var typeName = RuntimeRecordTypeNameFromParam(param.Type);
                    if (!_runtimeRecordTypes.TryGetValue(typeName, out var recordType))
                        continue;
                    foreach (var field in recordType.Fields)
                    {
                        AddRuntimeAction(new RuntimeAction(
                            $"runtime_{RuntimeStorageActionType(field.Type)}_set",
                            "",
                            "slot",
                            RuntimeRecordFieldSlotName(param.Slot, field.Name),
                            RuntimeRecordFieldSlotName(arg.Value, field.Name)));
                    }
                }
            }
        }

        void ParseFunctionCall(bool apply)
        {
            var call = ParseFunctionCallExpression();
            ExpectLine();

            if (!apply)
                return;

            if (!_runtimeFunctionMap.TryGetValue(call.Name, out var fn))
                throw new CompileError("SEMANTIC", "S050", call.NameToken.Line, call.NameToken.Column, $"Unknown function \"{call.Name}\".");

            AddFunctionArgumentSetupActions(fn, call.Args, call.NameToken);
            AddRuntimeAction(new RuntimeAction("function_call", "", "static", "", call.Name));
            AddFunctionArgumentCopyBackActions(fn, call.Args, call.NameToken);
        }

        void ValidateFunctionCallGraph()
        {
            if (_runtimeFunctions.Count == 0)
                return;

            var functionNames = new HashSet<string>(StringComparer.Ordinal);
            foreach (var fn in _runtimeFunctions)
                functionNames.Add(fn.Name);

            var graph = new Dictionary<string, List<string>>(StringComparer.Ordinal);
            foreach (var fn in _runtimeFunctions)
            {
                var calls = new List<string>();
                foreach (var action in fn.Actions)
                {
                    if (action.Op == "function_call")
                    {
                        if (!string.IsNullOrWhiteSpace(action.Target))
                            calls.Add(action.Target);
                    }
                    else if (action.Op == "function_call_assign")
                    {
                        if (!string.IsNullOrWhiteSpace(action.Value))
                            calls.Add(action.Value);
                    }
                }
                graph[fn.Name] = calls;

                foreach (var callee in calls)
                {
                    if (!functionNames.Contains(callee))
                        throw new CompileError("SEMANTIC", "S050", Current.Line, Current.Column, $"Function \"{fn.Name}\" calls unknown function \"{callee}\".");
                }
            }

            var state = new Dictionary<string, int>(StringComparer.Ordinal);
            var stack = new List<string>();

            void Visit(string name)
            {
                if (state.TryGetValue(name, out var existing))
                {
                    if (existing == 1)
                    {
                        var start = stack.IndexOf(name);
                        var cycle = start >= 0 ? stack.GetRange(start, stack.Count - start) : new List<string> { name };
                        cycle.Add(name);
                        throw new CompileError("SEMANTIC", "S170", Current.Line, Current.Column, "Recursive function call graph is not supported: " + string.Join(" -> ", cycle) + ".");
                    }
                    if (existing == 2)
                        return;
                }

                state[name] = 1;
                stack.Add(name);
                if (graph.TryGetValue(name, out var callees))
                {
                    foreach (var callee in callees)
                        Visit(callee);
                }
                stack.RemoveAt(stack.Count - 1);
                state[name] = 2;
            }

            foreach (var fn in _runtimeFunctions)
                Visit(fn.Name);
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

    }
}
