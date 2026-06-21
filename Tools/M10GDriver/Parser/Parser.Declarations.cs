using System.Globalization;
using System.Text;

static partial class Program
{
    sealed partial class Parser
    {
        // M18FG parser split: Declarations.

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
            if (CurrentWordIs("runtime"))
            {
                ParseRuntimeDefinition();
                return;
            }

            var isConst = false;
            if (IsKeyword("const"))
            {
                isConst = true;
                ExpectKeyword("const");
            }

            if (!CurrentIs("KEYWORD") || Current.Value is not ("string" or "int" or "float" or "double" or "bool" or "vec2" or "vec3" or "vec4" or "mat4" or "transform" or "quat" or "rect" or "circle" or "segment" or "line" or "ray" or "sphere" or "aabb" or "plane" or "complex" or "color" or "angle" or "var"))
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


        void ParseRuntimeDefinition()
        {
            ExpectWord("runtime", "P118", "Expected keyword \"runtime\" after define.");

            if (!CurrentIs("KEYWORD") || Current.Value is not ("int" or "bool" or "string"))
                throw new CompileError("PARSE", "P119", Current.Line, Current.Column, "Runtime define supports int, bool, and string slots.");

            var declaredType = Advance().Value;
            if (!IsKeyword("called"))
                throw new CompileError("PARSE", "P071", Current.Line, Current.Column, $"Expected keyword \"called\" after define runtime {declaredType}.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", $"runtime {declaredType} symbol name");
            CheckDuplicateSymbol(nameTok, "Runtime symbol");
            if (!IsKeyword("be"))
                throw new CompileError("PARSE", "P073", Current.Line, Current.Column, $"Expected keyword \"be\" after runtime {declaredType} symbol name.");
            ExpectKeyword("be");

            var parsed = declaredType switch
            {
                "int" => ParseRuntimeIntLiteral("define runtime int"),
                "bool" => ParseRuntimeBoolLiteral("define runtime bool"),
                "string" => ParseRuntimeStringStaticLiteral("define runtime string"),
                _ => throw new CompileError("PARSE", "P119", Current.Line, Current.Column, "Unsupported runtime slot type.")
            };

            ExpectLine();

            DefineRuntimeSymbol(nameTok.Value, declaredType == "string" ? "text" : declaredType, $"runtime_{declaredType}({parsed.Value})", isConst: false);
            AddRuntimeAction(new RuntimeAction($"runtime_{declaredType}_set", "", parsed.Kind, parsed.Value, nameTok.Value));
        }

        (string Kind, string Value) ParseRuntimeIntLiteral(string context)
        {
            var sign = "";
            if (CurrentIs("MINUS"))
            {
                sign = "-";
                Advance();
            }
            if (!CurrentIs("INT"))
                throw new CompileError("SEMANTIC", "S130", Current.Line, Current.Column, $"{context} requires an integer literal.");
            var valueTok = Advance();
            return ("static", sign + valueTok.Value);
        }

        (string Kind, string Value) ParseRuntimeBoolLiteral(string context)
        {
            if (!CurrentIs("BOOL"))
                throw new CompileError("SEMANTIC", "S140", Current.Line, Current.Column, $"{context} requires true or false.");
            return ("static", Advance().Value);
        }

        (string Kind, string Value) ParseRuntimeStringStaticLiteral(string context)
        {
            if (!IsKeyword("string"))
                throw new CompileError("SEMANTIC", "S141", Current.Line, Current.Column, $"{context} requires string literal syntax: string \"...\".");
            ExpectKeyword("string");
            var valueTok = Expect("STRING", "runtime string literal");
            return ("static", valueTok.Value);
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
                AddRuntimeAction(new RuntimeAction("command_arg_count", "", "slot", nameTok.Value, nameTok.Value));
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
            AddRuntimeAction(new RuntimeAction("command_arg_index", "", "index", index.ToString(CultureInfo.InvariantCulture), nameTok.Value));
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

            if (declaredType == "segment")
                return ParseSegmentLiteral();

            if (declaredType == "line")
                return ParseLineLiteral();

            if (declaredType == "ray")
                return ParseRayLiteral();

            if (declaredType == "sphere")
                return ParseSphereLiteral();

            if (declaredType == "aabb")
                return ParseAabbLiteral();

            if (declaredType == "plane")
                return ParsePlaneLiteral();

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

        ExprResult ParseSegmentLiteral()
        {
            ExpectWord("segment", "P190", "Expected segment literal.");
            ExpectWord("from", "P191", "Expected from in segment literal.");
            var a = ParseAddExpression(legacyQuotedStrings: false);
            if (a.Type != "vec2")
                throw new CompileError("SEMANTIC", "S190", Current.Line, Current.Column, "segment start must be vec2.");
            ExpectWord("to", "P192", "Expected to in segment literal.");
            var b = ParseAddExpression(legacyQuotedStrings: false);
            if (b.Type != "vec2")
                throw new CompileError("SEMANTIC", "S190", Current.Line, Current.Column, "segment end must be vec2.");
            var av = ToVector(a);
            var bv = ToVector(b);
            if (DistanceSquared(av, bv) < NumericEpsilon * NumericEpsilon)
                throw new CompileError("SEMANTIC", "S191", Current.Line, Current.Column, "segment endpoints cannot be equal.");
            return new ExprResult("segment", FormatSegment(av, bv), $"segment({a.Repr},{b.Repr})");
        }

        ExprResult ParseLineLiteral()
        {
            ExpectWord("line", "P193", "Expected line literal.");
            ExpectWord("from", "P194", "Expected from in line literal.");
            var a = ParseAddExpression(legacyQuotedStrings: false);
            if (a.Type != "vec2")
                throw new CompileError("SEMANTIC", "S192", Current.Line, Current.Column, "line start must be vec2.");
            ExpectWord("to", "P195", "Expected to in line literal.");
            var b = ParseAddExpression(legacyQuotedStrings: false);
            if (b.Type != "vec2")
                throw new CompileError("SEMANTIC", "S192", Current.Line, Current.Column, "line end must be vec2.");
            var av = ToVector(a);
            var bv = ToVector(b);
            if (DistanceSquared(av, bv) < NumericEpsilon * NumericEpsilon)
                throw new CompileError("SEMANTIC", "S193", Current.Line, Current.Column, "line points cannot be equal.");
            return new ExprResult("line", FormatSegment(av, bv), $"line({a.Repr},{b.Repr})");
        }

        ExprResult ParseRayLiteral()
        {
            ExpectWord("ray", "P196", "Expected ray literal.");
            ExpectWord("origin", "P197", "Expected origin in ray literal.");
            var origin = ParseAddExpression(legacyQuotedStrings: false);
            if (origin.Type != "vec3")
                throw new CompileError("SEMANTIC", "S194", Current.Line, Current.Column, "ray origin must be vec3.");
            ExpectWord("direction", "P198", "Expected direction in ray literal.");
            var direction = ParseAddExpression(legacyQuotedStrings: false);
            if (direction.Type != "vec3")
                throw new CompileError("SEMANTIC", "S194", Current.Line, Current.Column, "ray direction must be vec3.");
            var dir = ToVector(direction);
            var len = VectorLength(dir);
            if (len < NumericEpsilon)
                throw new CompileError("SEMANTIC", "S195", Current.Line, Current.Column, "ray direction cannot be zero.");
            var normalized = dir.Select(v => v / len).ToArray();
            return new ExprResult("ray", FormatRay(ToVector(origin), normalized), $"ray({origin.Repr},{direction.Repr})");
        }

        ExprResult ParseSphereLiteral()
        {
            ExpectWord("sphere", "P199", "Expected sphere literal.");
            ExpectWord("center", "P200", "Expected center in sphere literal.");
            var center = ParseAddExpression(legacyQuotedStrings: false);
            if (center.Type != "vec3")
                throw new CompileError("SEMANTIC", "S196", Current.Line, Current.Column, "sphere center must be vec3.");
            ExpectWord("radius", "P201", "Expected radius in sphere literal.");
            var radius = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(radius.Type))
                throw new CompileError("SEMANTIC", "S196", Current.Line, Current.Column, "sphere radius must be numeric.");
            var r = ToNumber(radius);
            if (r < 0)
                throw new CompileError("SEMANTIC", "S197", Current.Line, Current.Column, "sphere radius cannot be negative.");
            return new ExprResult("sphere", FormatSphere(ToVector(center), r), $"sphere({center.Repr},{radius.Repr})");
        }

        ExprResult ParseAabbLiteral()
        {
            ExpectWord("aabb", "P202", "Expected aabb literal.");
            ExpectWord("center", "P203", "Expected center in aabb literal.");
            var center = ParseAddExpression(legacyQuotedStrings: false);
            if (center.Type != "vec3")
                throw new CompileError("SEMANTIC", "S198", Current.Line, Current.Column, "aabb center must be vec3.");
            ExpectWord("size", "P204", "Expected size in aabb literal.");
            var size = ParseAddExpression(legacyQuotedStrings: false);
            if (size.Type != "vec3")
                throw new CompileError("SEMANTIC", "S198", Current.Line, Current.Column, "aabb size must be vec3.");
            var sv = ToVector(size);
            if (sv.Any(v => v < 0))
                throw new CompileError("SEMANTIC", "S199", Current.Line, Current.Column, "aabb size cannot be negative.");
            return new ExprResult("aabb", FormatAabb(ToVector(center), sv), $"aabb({center.Repr},{size.Repr})");
        }

        ExprResult ParsePlaneLiteral()
        {
            ExpectWord("plane", "P205", "Expected plane literal.");
            ExpectWord("normal", "P206", "Expected normal in plane literal.");
            var normal = ParseAddExpression(legacyQuotedStrings: false);
            if (normal.Type != "vec3")
                throw new CompileError("SEMANTIC", "S200", Current.Line, Current.Column, "plane normal must be vec3.");
            ExpectWord("distance", "P207", "Expected distance in plane literal.");
            var distance = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(distance.Type))
                throw new CompileError("SEMANTIC", "S200", Current.Line, Current.Column, "plane distance must be numeric.");
            var n = ToVector(normal);
            var len = VectorLength(n);
            if (len < NumericEpsilon)
                throw new CompileError("SEMANTIC", "S201", Current.Line, Current.Column, "plane normal cannot be zero.");
            var normalized = n.Select(v => v / len).ToArray();
            return new ExprResult("plane", FormatPlane(normalized, ToNumber(distance) / len), $"plane({normal.Repr},{distance.Repr})");
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

    }
}
