using System.Globalization;
using System.Text;

static partial class Program
{
    sealed partial class Parser
    {
        // M18FG parser split: Expressions.

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

            if (CurrentWordIs("segment"))
                return ParseSegmentLiteral();

            if (CurrentWordIs("line"))
                return ParseLineLiteral();

            if (CurrentWordIs("ray"))
                return ParseRayLiteral();

            if (CurrentWordIs("sphere"))
                return ParseSphereLiteral();

            if (CurrentWordIs("aabb"))
                return ParseAabbLiteral();

            if (CurrentWordIs("plane"))
                return ParsePlaneLiteral();

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

    }
}
