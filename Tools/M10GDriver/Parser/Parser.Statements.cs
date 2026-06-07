using System.Globalization;
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

    }
}
