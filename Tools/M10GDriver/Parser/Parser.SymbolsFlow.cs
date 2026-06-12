using System.Globalization;
using System.Text;

static partial class Program
{
    sealed partial class Parser
    {
        // M18FG parser split: SymbolsFlow.

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
            if (_dx12RendererNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S260", nameTok.Line, nameTok.Column, $"{label} \"{nameTok.Value}\" conflicts with an existing DX12 renderer name.");
            if (_dx12ShaderNames.Contains(nameTok.Value) || _dx12PipelineNames.Contains(nameTok.Value) || _dx12VertexBufferNames.Contains(nameTok.Value) || _dx12ObjectNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S280", nameTok.Line, nameTok.Column, $"{label} \"{nameTok.Value}\" conflicts with an existing DX12 shader, pipeline, vertex buffer, or object name.");
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

    }
}
